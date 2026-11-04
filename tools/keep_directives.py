import re


def restore(text):
    return re.sub(r'(?m)^(\s*)\(\* keep = "true" \*\) ([^\n]+)',
                  lambda m: m[1] + m[2] + ' //synthesis keep', text)
