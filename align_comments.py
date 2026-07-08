#!/usr/bin/env python3
import sys

KEYMAP = 'config/eyelash_sofle.keymap'
ROWS = 'ABCDE'


def get_labels(row):
    r = row.upper()
    n_right = 5 if r == 'E' else 6
    left = [f'L{r}{i}' for i in range(6)]
    middle = [f'| M{r} |']
    right = [f'R{r}{i}' for i in range(n_right)]
    return left + middle + right


def get_amp_positions(line):
    return [i for i, c in enumerate(line) if c == '&']


def make_comment(amp_positions, labels):
    if not amp_positions:
        return '//'
    labels = labels[:len(amp_positions)]
    max_end = max(p + len(l) for p, l in zip(amp_positions, labels)) + 1
    result = [' '] * max(max_end, 10)
    for pos, label in zip(amp_positions, labels):
        target = max(pos, 3)
        for j, c in enumerate(label):
            idx = target + j
            while idx >= len(result):
                result.append(' ')
            result[idx] = c
    result[0] = '/'
    result[1] = '/'
    result[2] = ' '
    return ''.join(result).rstrip()


def align(path):
    with open(path, 'r') as f:
        lines = f.read().split('\n')

    result_lines = []
    in_keymap = False
    in_bindings = False
    row_idx = 0
    i = 0

    while i < len(lines):
        line = lines[i]
        if 'compatible = "zmk,keymap"' in line:
            in_keymap = True
        if in_keymap and 'bindings = <' in line:
            in_bindings = True
            row_idx = 0
            result_lines.append(line)
            i += 1
            continue
        if in_bindings and line.strip() == '>;':
            in_bindings = False
            result_lines.append(line)
            i += 1
            continue
        if in_bindings and line.strip().startswith('//') and i + 1 < len(lines):
            next_line = lines[i + 1]
            if next_line.strip().startswith('&') and row_idx < len(ROWS):
                row = ROWS[row_idx]
                labels = get_labels(row)
                amp_positions = get_amp_positions(next_line)
                result_lines.append(make_comment(amp_positions, labels))
                row_idx += 1
                i += 1
                continue
        result_lines.append(line)
        i += 1

    with open(path, 'w') as f:
        f.write('\n'.join(result_lines))
    print(f'Aligned comments in {path}')


if __name__ == '__main__':
    align(sys.argv[1] if len(sys.argv) > 1 else KEYMAP)
