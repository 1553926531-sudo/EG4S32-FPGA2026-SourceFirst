
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BoardPinTests(unittest.TestCase):
    def test_board_manual_controls_and_preserved_media_connections(self):
                                                                     
                                                                       
        groups = {
            'key_col_n': 'E11 D11 C11 F10',
            'key_row_n': 'E10 C10 F9 D9',
            'switches': 'A9 A10 B10 A11 A12 B12 A13 A14',
            'led': 'B14 B15 B16 C15 C16 E13 E16 F16',
            'Digitron_Out': 'A4 A6 B8 E8 A7 B5 A8 C8',
            'DigitronCS_Out': 'C9 B6 A5 A3',
            'sd_dat': 'D14 D16 G14 F13',
        }
        expected = {f'{name}[{i}]': pin
                    for name, pins in groups.items() for i, pin in enumerate(pins.split())}
                                                                          
                                                           
        expected.update(dict(sd_clk='F15', sd_cmd='F14', hdmi_clk='T15',
                             hdmi_de='M9', hdmi_vs='P9', hdmi_hs='L10',
                             hdmi_scl='T4', hdmi_sda='R5',
                             i2s_mclk='M12', i2s_sdata='N12',
                             i2s_lrclk='P12', i2s_bclk='R16'))
        text = (ROOT / 'media_player.adc').read_text(encoding='utf-8')
        rows = re.findall(r'set_pin_assignment\s+\{([^}]+)\}\s+\{LOCATION\s*=\s*(\w+);', text)
        actual = dict(rows)
        self.assertEqual(len(rows), len(actual), 'a port has multiple assignments')
        self.assertEqual(len(rows), len(set(actual.values())), 'a physical pin has multiple ports')
        for port, pin in expected.items():
            with self.subTest(port=port):
                self.assertEqual(actual.get(port), pin)


if __name__ == '__main__':
    unittest.main()
