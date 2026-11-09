"""Generate the log and quarter-wave ROMs for the v3 pipeline."""

import math
from pathlib import Path


directory = Path(__file__).resolve().parents[1]
steps = 1024
log = [round(-2 * math.log1p(index / steps) * 2**32) for index in range(steps + 1)]
with (directory / 'log_norm_q832.mem').open('w', encoding='ascii') as table:
    for value in log:
        table.write(f'{value & (2**40 - 1):010X}\n')

sine = [round(math.sin(math.pi * index / (2 * steps)) * 2**28) for index in range(steps + 1)]
with (directory / 'sin_pair_q428.mem').open('w', encoding='ascii') as table:
    for index, value in enumerate(sine):
        next_value = sine[min(index + 1, steps)]
        table.write(f'{value:08X}{next_value:08X}\n')
