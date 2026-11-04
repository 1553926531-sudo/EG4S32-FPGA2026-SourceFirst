#include <stdint.h>
#include <stddef.h>

typedef uint32_t u32;
typedef uint16_t u16;
typedef uint8_t u8;
typedef uint64_t u64;
#define REG ((volatile u32 *)0x20000000)
#define CARD ((volatile u32 *)0x20001000)
#define RESPONSE ((volatile u32 *)0x20002000)
#define PIXELS 8192u
#define AUDIO 0x100000u

typedef struct { u32 cluster, bytes, flags, hash; } File;
typedef struct { u32 cluster, sectors, contiguous; } Directory;
typedef struct { u32 index, cluster, file; } MapCache;
typedef struct { u32 sample, length; char text[80]; } Cue;
static File files[512];
static Directory directories[64];
static MapCache maps[4];
static u16 filename[260];
static u32 counts[4],fat_start,fat_length,heap_start,cluster_count,cluster_shift;
static u32 root_cluster,volume_start,volume_length,exfat,pak_found;
static u32 card_cached,read_cached_file,read_cached_sector;
static u32 selected,kind,is_legacy,width,height,stride,offset,top_down,pixel32;
static u32 samples,audio_sectors,row_sectors,cue_count,lyric_file;
static u32 resume_position,resume_index,resume_previous;
static u32 fault;

void *memset(void *p,int value,size_t n) { u8 *d=p; while(n--)*d++=(u8)value; return p; }
void *memcpy(void *p,const void *s,size_t n) { u8 *d=p;const u8 *q=s;while(n--)*d++=*q++;return p; }
static u16 le16(const u8 *p) { return p[0]|((u16)p[1]<<8); }
static u32 le32(const u8 *p) { return le16(p)|((u32)le16(p+2)<<16); }
static u64 le64(const u8 *p) { return le32(p)|((u64)le32(p+4)<<32); }
static u32 upper(u32 c) { return c>='a' && c<='z'?c-32:c; }
static u32 mask(void) { return (1u<<cluster_shift)-1; }
static int valid_cluster(u32 c) { return c>=2 && c-2<cluster_count; }
static u64 file_size(u32 id) { return files[id].bytes|((u64)(files[id].flags&511)<<32); }
static void invalidate(void) { card_cached=~0u;read_cached_file=~0u; }
static int card_read(u32 lba) {
 if(card_cached==lba)return 1;
 read_cached_file=~0u;
 REG[4]=lba;REG[5]=1;
 while(REG[3]&1){}
 if(REG[3]&2){fault=0x41;invalidate();return 0;}
 card_cached=lba;return 1;
}
static int sector_copy(u32 lba,u8 *data) {
 if(!card_read(lba))return 0;
 for(u32 n=0;n<128;n++)((u32 *)data)[n]=CARD[n];
 return 1;
}
static u32 next_cluster(u32 cluster) {
 if(!valid_cluster(cluster) || (cluster>>7)>=fat_length){fault=0x44;return 0;}
 if(!card_read(fat_start+(cluster>>7)))return 0;
 u32 next=CARD[cluster&127];
 if(!exfat)next&=0x0fffffff;
 return next;
}
static int map_sector(u32 id,u32 sector,u32 channel,u32 *physical) {
 File *f=&files[id];
 if(((u64)sector<<9)>=file_size(id) || !valid_cluster(f->cluster)){fault=0x53;return 0;}
 u32 index=sector>>cluster_shift,cluster=f->cluster,from=0;
 if(f->flags&512)cluster+=index;
 else {
  MapCache *m=&maps[channel];
  if(m->file==id && m->index<=index){cluster=m->cluster;from=m->index;}
  if(index>=cluster_count){fault=0x53;return 0;}
  while(from<index){
   u32 next=next_cluster(cluster);
   if(fault || !valid_cluster(next) || next==cluster){fault=0x53;return 0;}
   cluster=next;from++;
  }
 }
 if(!valid_cluster(cluster)){fault=0x53;return 0;}
 maps[channel]=(MapCache){index,cluster,id};
 *physical=heap_start+((cluster-2)<<cluster_shift)+(sector&mask());
 return 1;
}
static int file_sector(u32 id,u32 sector,u32 channel) {
 if(read_cached_file==id && read_cached_sector==sector && card_cached!=~0u)return 1;
 u32 physical;
 if(!map_sector(id,sector,channel,&physical) || !card_read(physical))return 0;
 read_cached_file=id;read_cached_sector=sector;return 1;
}
static u32 word(u32 id,u32 address,u32 bytes,u32 channel) {
 if((u64)address+bytes>file_size(id)){fault=0x53;return 0;}
 if(!file_sector(id,address>>9,channel))return 0;
 u32 a=CARD[(address&511)>>2],shift=(address&3)*8;
 u32 result=a>>shift;
 if((address&3)+bytes>4){
  if((address&511)>=508){if(!file_sector(id,(address>>9)+1,channel))return 0;}
  u32 b=CARD[((address+4)&511)>>2];
  result|=b<<(32-shift);
 }
 if(bytes<4)result&=(1u<<(bytes*8))-1;
 return result;
}
static u32 hash_character(u32 h,u32 c) { return ((h<<5)|(h>>27))^upper(c); }
static int store_entry(u32 cluster,u64 bytes,u32 contiguous,u32 directory,u32 parent,u32 length,u32 *queue_end) {
 if(bytes>>41){fault=0x48;return 0;}
 if(directory){
  if(!valid_cluster(cluster) || *queue_end>=64){fault=0x46;return 0;}
  for(u32 n=0;n<*queue_end;n++)if(directories[n].cluster==cluster){fault=0x46;return 0;}
  directories[(*queue_end)++]=(Directory){cluster,(u32)((bytes+511)>>9),contiguous};return 1;
 }
 if(!bytes || !valid_cluster(cluster) || length<4)return 1;
 u32 ext=0;
 for(u32 n=length-3;n<length;n++)ext=(ext<<8)|upper(filename[n]);
 if(filename[length-4]!='.')return 1;
 u32 type,id;
 if(ext==0x544656)type=0;
 else if(ext==0x424d50)type=1;
 else if(ext==0x574156)type=2;
 else if(ext==0x4c5243)type=3;
 else if(ext==0x50414b){if(pak_found)return 1;pak_found=1;id=511;goto save;}
 else return 1;
 if(counts[type]>=(type==3?127u:128u)){fault=0x47;return 0;}
 id=(type<<7)|counts[type]++;
save:;
 u32 h=parent;
 for(u32 n=0;n<length-4;n++)h=hash_character(h,filename[n]);
 files[id]=(File){cluster,(u32)bytes,(u32)(bytes>>32)|(contiguous?512u:0u),h};
 REG[8]=id*8;
 for(u32 n=0;n<32;n+=4){
  u32 packed=0;
  for(u32 b=0;b<4;b++){
   u32 c=n+b<length?filename[n+b]:32;
   if(c<32 || c>126)c='?';
   packed|=c<<(b*8);
  }
  REG[9]=packed;
 }
 return 1;
}
static u16 set_sum(u16 sum,const u8 *entry,int first) {
 for(u32 n=0;n<32;n++)if(!first || (n!=2 && n!=3))sum=((sum>>1)|(sum<<15))+entry[n];
 return sum;
}
static int enumerate(void) {
 u8 data[512] __attribute__((aligned(4)));
 u32 begin=0,end=1;
 directories[0]=(Directory){root_cluster,0,0};
 while(begin<end){
  Directory dir=directories[begin++];
  u32 cluster=dir.cluster,sector=0,steps=0,ended=0;
  u32 lfn_sequence=0,lfn_sum=0,lfn_valid=0;
  u32 remaining=0,ex_stream=0,ex_names=0,name_position=0,length=0;
  u32 pending_cluster=0,pending_contiguous=0,pending_directory=0;
  u64 pending_bytes=0,pending_valid=0;
  u16 checksum=0,expected_checksum=0;
  while(!ended){
   if(!valid_cluster(cluster) || steps>cluster_count){fault=0x44;return 0;}
   if(!sector_copy(heap_start+((cluster-2)<<cluster_shift)+sector,data))return 0;
   for(u32 i=0;i<512;i+=32){
    u8 *e=data+i;
    if(!e[0]){ended=1;break;}
    if(exfat){
     if(e[0]==0x85){
      remaining=e[1];expected_checksum=le16(e+2);checksum=set_sum(0,e,1);
      ex_stream=0;ex_names=0;name_position=0;length=0;pending_directory=e[4]&16;
      if(remaining<2 || remaining>18){remaining=0;continue;}
     }else if(remaining){
      checksum=set_sum(checksum,e,0);remaining--;
      if(e[0]==0xc0 && !ex_stream){
       ex_stream=1;length=e[3];pending_contiguous=e[1]&2;
       pending_valid=le64(e+8);pending_cluster=le32(e+20);pending_bytes=le64(e+24);
      }else if(e[0]==0xc1 && ex_stream){
       ex_names=1;
       for(u32 n=0;n<15 && name_position<length;n++)filename[name_position++]=le16(e+2+n*2);
      }else {remaining=0;continue;}
      if(!remaining && ex_stream && ex_names){
       if(checksum!=expected_checksum || !length || name_position!=length || pending_valid!=pending_bytes){fault=0x45;return 0;}
       if(!store_entry(pending_cluster,pending_bytes,pending_contiguous,pending_directory,dir.cluster,length,&end))return 0;
      }
     }
    }else {
     if(e[0]==0xe5){lfn_valid=0;continue;}
     if(e[11]==15){
      u32 seq=e[0]&31;
      if(!seq || seq>20 || (e[0]&0xa0) || e[12] || le16(e+26)){lfn_valid=0;continue;}
      if(e[0]&64){lfn_valid=1;lfn_sum=e[13];memset(filename,255,sizeof filename);}
      else if(!lfn_valid || seq+1!=lfn_sequence || lfn_sum!=e[13])lfn_valid=0;
      lfn_sequence=seq;
      const u8 positions[13]={1,3,5,7,9,14,16,18,20,22,24,28,30};
      for(u32 n=0;n<13;n++)if((seq-1)*13+n<255)filename[(seq-1)*13+n]=le16(e+positions[n]);
      continue;
     }
     if((e[11]&8) || e[0]=='.'){lfn_valid=0;continue;}
     u32 sum=0;
     for(u32 n=0;n<11;n++)sum=(((sum&1)<<7)|(sum>>1))+e[n],sum&=255;
     length=0;
     if(lfn_valid && lfn_sequence==1 && lfn_sum==sum){while(length<255 && filename[length] && filename[length]!=65535)length++;}
     else {
      for(u32 n=0;n<8;n++)if(e[n]!=' ')filename[length++]=e[n];
      if(e[8]!=' '){filename[length++]='.';for(u32 n=8;n<11;n++)if(e[n]!=' ')filename[length++]=e[n];}
     }
     lfn_valid=0;
     if(!store_entry(((u32)le16(e+20)<<16)|le16(e+26),le32(e+28),0,e[11]&16,dir.cluster,length,&end))return 0;
    }
   }
   if(ended)break;
   if(dir.contiguous && dir.sectors && --dir.sectors==0)break;
   if(sector==mask()){
    sector=0;steps++;
    u32 next=dir.contiguous?cluster+1:next_cluster(cluster);
    if(fault)return 0;
    if(next>=(exfat?0xfffffff8u:0x0ffffff8u))break;
    if(!valid_cluster(next) || next==cluster){fault=0x44;return 0;}
    cluster=next;
   }else sector++;
  }
 }
 return 1;
}
static int mount(void) {
 u8 b[512] __attribute__((aligned(4)));
 volume_start=0;
 for(u32 attempt=0;attempt<2;attempt++){
  if(!sector_copy(volume_start,b))return 0;
  if(le16(b+510)!=0xaa55){fault=0x42;return 0;}
  exfat=le32(b+3)==0x41465845 && le32(b+7)==0x20202054;
  if(exfat){
   u64 length=le64(b+72);
   cluster_shift=b[109];fat_length=le32(b+84);cluster_count=le32(b+92);root_cluster=le32(b+96);
   u32 fat_offset=le32(b+80),heap_offset=le32(b+88),nfats=b[110];
   if(b[108]!=9 || cluster_shift>16 || !cluster_count || cluster_count>0xfffffff5u ||
    !fat_length || (nfats!=1 && nfats!=2) || fat_offset<24 ||
    (u64)fat_offset+(u64)fat_length*nfats>heap_offset ||
    (u64)heap_offset+((u64)cluster_count<<cluster_shift)>length ||
    length>0xffffffffu || (u64)volume_start+length>0x100000000ull ||
    ((u64)cluster_count+129)/128>fat_length){fault=0x43;return 0;}
   volume_length=(u32)length;
   fat_start=volume_start+fat_offset+((nfats==2 && (le16(b+106)&1))?fat_length:0);
   heap_start=volume_start+heap_offset;
  }else if(le16(b+11)==512 && b[13] && !(b[13]&(b[13]-1)) && !le16(b+17) && le32(b+36)){
   u32 reserved=le16(b+14),nfats=b[16],spc=b[13];
   fat_length=le32(b+36);volume_length=le32(b+32);root_cluster=le32(b+44)&0x0fffffff;
   u32 flags=le16(b+40);
   if(!reserved || (nfats!=1 && nfats!=2) || le16(b+19) || le16(b+22) ||
    (u64)reserved+(u64)fat_length*nfats>=volume_length ||
    (u64)volume_start+volume_length>0x100000000ull || ((flags&128) && (flags&15)>=nfats)){
    fault=0x43;return 0;
   }
   cluster_shift=0;while((1u<<cluster_shift)!=spc)cluster_shift++;
   cluster_count=(volume_length-reserved-fat_length*nfats)>>cluster_shift;
   if(cluster_count<65525 || cluster_count>0x0ffffff5 || (cluster_count+129u)/128>fat_length){fault=0x43;return 0;}
   fat_start=volume_start+reserved+((flags&128)?fat_length*(flags&15):0);
   heap_start=volume_start+reserved+fat_length*nfats;
  }else {
   if(!attempt){
    u32 part=0;
    for(u32 n=446;n<510;n+=16)if(b[n+4]==7 || b[n+4]==11 || b[n+4]==12){part=le32(b+n+8);if(part)break;}
    if(part){volume_start=part;continue;}
   }
   fault=0x42;return 0;
  }
  if(!valid_cluster(root_cluster)){fault=0x43;return 0;}
  return enumerate();
 }
 fault=0x42;return 0;
}
static u32 crc_sector(void) {
 u32 crc=~0u;
 for(u32 n=0;n<127;n++){
  u32 value=CARD[n];
  for(u32 byte=0;byte<4;byte++){
   crc^=value&255;value>>=8;
   for(u32 bit=0;bit<8;bit++)crc=(crc>>1)^((crc&1)?0xedb88320u:0);
  }
 }
 return ~crc;
}
static int raw_header(u32 id,int probe) {
 u64 bytes=file_size(id);
 if(!bytes || (bytes&511) || !file_sector(id,0,0)){if(!fault)fault=0x52;return 0;}
 if(CARD[0]!=0x314d4654 || CARD[1]!=3 || CARD[2]!=1280 || CARD[3]!=800 ||
  CARD[4]!=1 || CARD[5]!=1024000 || !CARD[6] || CARD[6]>1000000 || CARD[18]>600 || CARD[20]>600 ||
  (!probe && !is_legacy && (CARD[18] || CARD[20]))){fault=0x52;return 0;}
 if(probe){
  if(crc_sector()!=CARD[127]){fault=0x52;return 0;}
  REG[17]=1;REG[18]=CARD[18];REG[19]=CARD[20];
 }
 REG[23]=(u32)(bytes>>9);return 1;
}
static int next_cue(u32 *position,u32 previous,u32 index,Cue *cue) {
 u32 phase=0,digits=0,minutes=0,seconds=0,fraction=0,fractions=0,length=0,valid=0;
 memset(cue->text,' ',80);
 while(1){
  int last=*position>=files[lyric_file].bytes;
  u32 c=last?10:word(lyric_file,(*position)++,1,3);
  if(fault)return -1;
  if(c==10){
   if(valid){
    if(fractions==1)fraction*=100;else if(fractions==2)fraction*=10;
    u32 sample=(minutes*60+seconds)*48000+fraction*48;
    if(index>=4096 || minutes>=60 || seconds>=60 || sample>=samples || (index && sample<=previous)){fault=0x58;return -1;}
    cue->sample=sample;cue->length=length;return 1;
   }
   if(last)return 0;
   phase=0;digits=0;length=0;continue;
  }
  if(c==13)continue;
  int digit=c>='0' && c<='9';
  if(phase==0){if(c=='['){phase=1;minutes=0;seconds=0;fraction=0;fractions=0;digits=0;}}
  else if(phase==1){if(digit && minutes<60){minutes=minutes*10+c-'0';digits=1;}
   else if(c==':' && digits){phase=2;digits=0;}else phase=5;}
  else if(phase==2){if(digit && seconds<60){seconds=seconds*10+c-'0';digits=1;}
   else if(c=='.' && digits)phase=3;
   else if(c==']' && digits && seconds<60){phase=4;valid=1;}else phase=5;}
  else if(phase==3){if(digit){if(fractions<3){fraction=fraction*10+c-'0';fractions++;}}
   else if(c==']' && seconds<60){phase=4;valid=1;}else phase=5;}
  else if(phase==4){if(length==78 || c<32 || c>126){fault=0x58;return -1;}cue->text[length++]=(char)c;}
 }
}
static int parse_bmp(void) {
 u32 signature=word(selected,0,2,0),dib=word(selected,14,4,0);
 offset=word(selected,10,4,0);width=word(selected,18,4,0);
 int32_t signed_height=(int32_t)word(selected,22,4,0);
 u32 planes=word(selected,26,2,0),bits=word(selected,28,2,0),compression=word(selected,30,4,0);
 top_down=signed_height<0;height=top_down?-(u32)signed_height:(u32)signed_height;pixel32=bits==32;
 if(fault)return 0;
 if(signature!=0x4d42 || dib<40 || dib>124 || offset<14+dib || !width || width>2048 || !height || height>2048 ||
  planes!=1 || (bits!=24 && bits!=32) || compression){fault=0x54;return 0;}
 stride=(width*(pixel32?4u:3u)+3)&~3u;
 if((u64)offset+(u64)stride*height>file_size(selected)){fault=0x54;return 0;}
 row_sectors=(width+127)>>7;samples=1;audio_sectors=1;cue_count=0;
 return 1;
}
static int parse_wav(void) {
 u32 riff=word(selected,0,4,0),end=word(selected,4,4,0),wave=word(selected,8,4,0);
 if(fault)return 0;
 if(riff!=0x46464952 || wave!=0x45564157 || end<36 || end>0xfffffff7u || (u64)end+8>file_size(selected)){fault=0x55;return 0;}
 end+=8;u32 pos=12,format=0,data=0,data_bytes=0;
 for(u32 steps=0;steps<4096 && pos<=end-8;steps++){
  u32 tag=word(selected,pos,4,0),size=word(selected,pos+4,4,0);
  if(fault)return 0;
  if((u64)pos+8+size>end){fault=0x55;return 0;}
  if(tag==0x20746d66){
   if(format || size<16){fault=0x55;return 0;}format=1;
   if(word(selected,pos+8,4,0)!=0x00020001 || word(selected,pos+12,4,0)!=48000 ||
    word(selected,pos+16,4,0)!=192000 || word(selected,pos+20,4,0)!=0x00100004){fault=0x56;return 0;}
  }else if(tag==0x61746164){
   if(data || !size || (size&3)){fault=0x55;return 0;}data=1;offset=pos+8;data_bytes=size;
  }
  if(format && data)break;
  u64 next=(u64)pos+8+size+(size&1);if(next>0xffffffffu)break;pos=(u32)next;
 }
 if(!format || !data){fault=0x55;return 0;}
 samples=data_bytes>>2;if(samples>172800000u){fault=0x56;return 0;}
 width=1;height=1;stride=4;row_sectors=1;top_down=1;pixel32=1;
 audio_sectors=(samples+126)/127;cue_count=0;lyric_file=~0u;
 for(u32 n=0;n<counts[3];n++)if(files[384+n].hash==files[selected].hash){
  if(lyric_file!=~0u || !files[384+n].bytes || file_size(384+n)>1048576){fault=0x57;return 0;}
  lyric_file=384+n;
 }
 if(lyric_file!=~0u){
  u32 position=0,previous=0;Cue cue;
  while(next_cue(&position,previous,cue_count,&cue)>0){previous=cue.sample;cue_count++;}
  if(fault)return 0;
 }
 resume_position=0;resume_index=0;resume_previous=0;return 1;
}
static int prepare_file(void) {
 u32 selection=REG[1];selected=selection&511;kind=(selection>>9)&3;is_legacy=(selection>>11)&1;
 fault=0;invalidate();for(u32 n=0;n<4;n++)maps[n].file=~0u;
 if(!file_size(selected)){fault=0x51;return 0;}
 if(is_legacy || kind==0)return raw_header(selected,0);
 if(kind==1){if(!parse_bmp())return 0;}
 else if(kind==2){if(!parse_wav())return 0;}
 else {fault=0x51;return 0;}
 REG[23]=AUDIO+audio_sectors;return 1;
}
static void clear_response(void) { for(u32 n=0;n<128;n++)RESPONSE[n]=0; }
static int copy_pcm(u32 address,u32 count) {
 u32 output=0;
 while(count){
  if(!file_sector(selected,address>>9,2))return 0;
  u32 within=address&511,shift=(within&3)*8;
  u32 available=(512-within)/4;
  if(available>count)available=count;
  if(shift){
   for(u32 n=0;n<available;n++){
    u32 index=(within>>2)+n;
    RESPONSE[output++]=(CARD[index]>>shift)|(CARD[index+1]<<(32-shift));
   }
  }else for(u32 n=0;n<available;n++)RESPONSE[output++]=CARD[(within>>2)+n];
  address+=available*4;count-=available;
  if(count && (address&511)){
   RESPONSE[output++]=word(selected,address,4,2);
   if(fault)return 0;
   address+=4;count--;
  }
 }
 return 1;
}
static int synthesize(u32 lba) {
 clear_response();
 if(lba==0){
  const u32 base[24]={0x314d4654,3,1280,800,1,1024000,1,1000,1,1,2,AUDIO,
   0,48000,16,2,5000,0,1,1,1,3,2,0};
  for(u32 n=0;n<24;n++)RESPONSE[n]=base[n];
  RESPONSE[12]=samples;RESPONSE[17]=AUDIO+audio_sectors;RESPONSE[23]=32+cue_count;
 }else if(lba==1 || lba==2){
  RESPONSE[0]=0x32474d49;RESPONSE[1]=lba==1?0:0x80000000;
  RESPONSE[2]=width;RESPONSE[3]=height;RESPONSE[4]=PIXELS;RESPONSE[5]=row_sectors;RESPONSE[6]=row_sectors*height;
 }else if(lba==3 || lba==4){
  RESPONSE[0]=0x33445541;RESPONSE[1]=lba-3;RESPONSE[2]=AUDIO;RESPONSE[3]=samples;RESPONSE[4]=audio_sectors;
  RESPONSE[6]=cue_count?32:0;RESPONSE[7]=cue_count;
 }else if(lba>=32 && lba<32+cue_count){
  u32 target=lba-32,position=0,index=0,previous=0;Cue cue;
  if(target==resume_index){position=resume_position;index=resume_index;previous=resume_previous;}
  while(1){
   if(next_cue(&position,previous,index,&cue)<=0)return 0;
   previous=cue.sample;
   if(index++==target)break;
  }
  resume_position=position;resume_index=index;resume_previous=previous;
  RESPONSE[0]=0x33455543;RESPONSE[1]=cue.sample;RESPONSE[2]=target;RESPONSE[3]=cue.length;
  for(u32 n=0;n<20;n++)RESPONSE[4+n]=le32((const u8 *)cue.text+n*4);
 }else if(lba>=PIXELS && lba<PIXELS+row_sectors*height){
  u32 index=lba-PIXELS,row=index/row_sectors,x=(index%row_sectors)*128;
  if(!top_down)row=height-1-row;
  for(u32 n=0;n<128;n++,x++){
   u32 color=(kind==2 && x==0)?0x101820:0;
   if(x<width && kind==1)color=word(selected,offset+row*stride+x*(pixel32?4u:3u),pixel32?4:3,1)&0xffffff;
   RESPONSE[n]=color;
   if(fault)return 0;
  }
 }else if(lba>=AUDIO && lba<AUDIO+audio_sectors){
  u32 index=(lba-AUDIO)*127;
  u32 count=samples-index;if(count>127)count=127;
  if(kind!=1 && !copy_pcm(offset+index*4,count))return 0;
 }else return 0;
 return !fault;
}
int main(void) {
 invalidate();for(u32 n=0;n<4;n++)maps[n].file=~0u;
 while(!(REG[0]&1)){}
 if(!mount())goto fatal;
 if(!counts[0] && !counts[1] && !counts[2] && pak_found){
  is_legacy=1;if(!raw_header(511,1))goto fatal;
  REG[16]=3;
 }else {
  REG[17]=counts[0];REG[18]=counts[1];REG[19]=counts[2];REG[16]=1;
 }
 while(1){
  u32 status=REG[0];
  if(status&2){
   REG[24]=0;
   int ok=prepare_file();REG[24]=fault;REG[6]=ok?(is_legacy || kind==0?1:3):0;
  }else if(status&4){
   u32 lba=REG[2];fault=0;
   if(is_legacy || kind==0){
    u32 physical;
    if(map_sector(selected,lba,0,&physical)){
     u32 first=lba&~mask(),length=mask()+1;
     u32 total=(u32)(file_size(selected)>>9);
     if(total-first<length)length=total-first;
     REG[10]=first;REG[11]=physical-(lba-first);REG[12]=length;REG[13]=1;
     invalidate();REG[4]=physical;REG[5]=2;
    }else {REG[24]=fault;REG[7]=2;}
   }else {
    int ok=synthesize(lba);REG[24]=fault;REG[7]=ok?1:2;
   }
  }
 }
fatal:
 REG[24]=fault;while(1){}
}
