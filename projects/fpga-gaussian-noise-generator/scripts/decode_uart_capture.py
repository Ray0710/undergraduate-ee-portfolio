"""Usage: python decode_uart_capture.py capture.bin decoded.txt
Reads an already saved binary UART capture in the AWGN 12-byte packet format.
"""
from pathlib import Path
import argparse,struct,json
p=argparse.ArgumentParser();p.add_argument('capture');p.add_argument('output');a=p.parse_args()
raw=Path(a.capture).read_bytes();pos=0;prev=None;rows=[];skipped=0;gaps=0
while pos+12<=len(raw):
    if raw[pos:pos+2]!=b'\xa5\x5a':pos+=1;skipped+=1;continue
    seq,z1,z2=struct.unpack_from('<Hii',raw,pos+2)
    if prev is not None and seq!=(prev+1)&65535:gaps+=1
    rows.append((seq,z1,z2,z1/2**28,z2/2**28));prev=seq;pos+=12
dest=Path(a.output)
if dest.exists():raise SystemExit('Output exists; choose another filename.')
with dest.open('w',encoding='utf-8') as f:
    f.write('sequence z1_Q28 z2_Q28 z1_real z2_real\n')
    for r in rows:f.write(f'{r[0]} {r[1]} {r[2]} {r[3]:.12f} {r[4]:.12f}\n')
print(json.dumps({'packets':len(rows),'skipped_bytes':skipped,'trailing_bytes':len(raw)-pos,'sequence_discontinuities':gaps}))
