
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]


def transactions():
    t = []
    def add(dev, reg, value, note):
        t.append(dict(device=dev, register=reg, value=value, note=note))
    for dev,reg,value,note in [
        (0x72,0x08,0x34,"TMDS powered down; 24-bit, H/V enabled, falling-edge input"),
        (0x72,0x05,0x01,"Assert software reset"),
        (0x72,0x0C,0x03,"PLL filter on"),
        (0x72,0x0D,0x02,"Mute audio during initialization"),
        (0x72,0x80,0x00,"24-bit TMDS Yellow clock range"),
        (0x72,0x82,0x25,"1x TMDS clock, termination, bias"),
        (0x72,0x83,0x59,"Yellow-range PLL control"),
        (0x72,0x84,0x31,"Yellow-range PLL control"),
        (0x72,0x85,0x01,"Yellow-range PLL control"),
        (0x72,0x49,0x00,"RGB input, no RGB-to-YCbCr converter"),
        (0x72,0x4A,0x00,"No CSC/dither/demux/embedded-sync extraction"),
        (0x72,0x33,0x00,"EXTERNAL DE; internal DE generator explicitly disabled; +/+"),
        (0x7A,0x14,0x00,"Audio disabled until clocks/format are configured"),
        (0x7A,0x2F,0x21,"HDMI mode, 24-bit packetizer, audio layout 0"),
    ]: add(dev,reg,value,note)
                                                                     
    avi = [0x02,0x00,0x08,0x00,0x00] + [0]*8
    avi_frame = [0x82,0x02,0x0D,(-sum([0x82,0x02,0x0D]+avi)) & 255]+avi
    for i,b in enumerate(avi_frame): add(0x7A,0x40+i,b,"AVI InfoFrame")
    for reg,value,note in [
        (0x01,0x02,"Enable N/CTS packets, hardware-generated CTS"),
        (0x02,0x01,"MCLK=256Fs"),
        (0x03,0x00,"N[7:0]; N=6144"),(0x04,0x18,"N[15:8]"),(0x05,0x00,"N[19:16]"),
        (0x1C,0xE4,"FIFO0 from SD0; layout 0"),
        (0x1D,0x40,"Rising BCLK capture; WS-low left; left aligned; MSB; Philips delay"),
        (0x1E,0x00,"Consumer LPCM channel status byte 0"),
        (0x1F,0x00,"General category"),(0x20,0x00,"Channel/source defaults"),
        (0x21,0x02,"Channel status Fs=48kHz"),
        (0x22,0xD2,"Original Fs=48kHz, sample word length=16"),
        (0x23,0x00,"Disable downsampling"),(0x24,0x02,"I2S input length=16 bits"),
    ]: add(0x7A,reg,value,note)
    audio = [0x11,0x0D,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00]
    audio_frame=[0x84,1,10,(-sum([0x84,1,10]+audio))&255]+audio
    for i,b in enumerate(audio_frame): add(0x7A,0x80+i,b,"Audio InfoFrame: PCM stereo, 48kHz/16bit")
    for dev,reg,value,note in [
        (0x72,0x08,0x35,"Power up, falling-edge capture"),
        (0x72,0x05,0x00,"Release software reset"),
        (0x72,0x08,0x35,"Normal TMDS operation"),
        (0x7A,0x3E,0x33,"Enable/repeat AVI and Audio InfoFrames"),
        (0x7A,0x14,0x11,"Enable SD0 and audio stream; MCLK stable for seconds"),
        (0x72,0x0D,0x00,"Normal video/audio, clear software audio mute"),
    ]: add(dev,reg,value,note)
    assert sum(avi_frame)%256==0 and sum(audio_frame)%256==0
    return t


def main():
    t=transactions()
    lines=["// Generated from explicit register list in tools/gen_hdmi_lut.py.",
           "// Candidate configuration, not a hardware pass record.",
           "module media_hdmi_lut(input wire [9:0] index, output reg [31:0] data);",
           "always @* begin case(index)"]
    for i,row in enumerate(t):
        lines.append(f"10'd{i}:data=32'h{row['device']:02x}00{row['register']:02x}{row['value']:02x}; // {row['note']}")
    lines += ["default:data=32'hffffffff;endcase end", "endmodule", ""]
    (ROOT/"rtl/media_hdmi_lut.v").write_text("\n".join(lines),encoding="utf-8")
    (ROOT/"HDMI_REGISTERS.json").write_text(json.dumps(t,indent=2),encoding="utf-8")
    print(f"Generated {len(t)} explicit I2C writes; both InfoFrame checksums valid.")


if __name__=="__main__":main()
