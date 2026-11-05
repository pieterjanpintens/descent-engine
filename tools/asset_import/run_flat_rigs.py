"""Runs import_flat_rigs.py over every monster and hero figure, in groups of at most GROUP_SIZE per run (one process per group, a pause
between groups). Usage: python run_flat_rigs.py <bundles folder> [log file]"""
import os
import re
import subprocess
import sys
import time

GROUP_SIZE = 8
PAUSE_SECONDS = 5
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def targets():
    text = open(os.path.join(ROOT, "scripts", "MonsterDisplay.gd"), encoding="utf-8").read()
    block = re.search(r"const REAL_MONSTERS := \[(.*?)\n\]", text, re.DOTALL).group(1)
    found = re.findall(r'"folder"\s*:\s*"([^"]+)"', block)
    heroes = re.search(r"const HERO_NAMES[^=]*=\s*\[(.*?)\]", open(os.path.join(ROOT, "scripts", "HeroCatalog.gd"), encoding="utf-8").read(), re.DOTALL).group(1)
    for hero in re.findall(r'"([^"]+)"', heroes):
        for act in (0, 1):
            found.append("hero:%s:%d" % (hero.lower(), act))
    return found


def main():
    bundles = sys.argv[1]
    log = open(sys.argv[2], "a", encoding="utf-8") if len(sys.argv) > 2 else sys.stdout
    all_targets = targets()
    groups = [all_targets[i:i + GROUP_SIZE] for i in range(0, len(all_targets), GROUP_SIZE)]
    log.write("%d figures in %d groups of at most %d\n" % (len(all_targets), len(groups), GROUP_SIZE))
    log.flush()
    for number, group in enumerate(groups, 1):
        log.write("--- group %d/%d: %s\n" % (number, len(groups), ", ".join(group)))
        log.flush()
        result = subprocess.run([sys.executable, os.path.join(HERE, "import_flat_rigs.py"), bundles] + group, stdout=log, stderr=subprocess.STDOUT)
        log.write("--- group %d finished (exit %d)\n" % (number, result.returncode))
        log.flush()
        if number < len(groups):
            time.sleep(PAUSE_SECONDS)
    log.write("ALL DONE\n")
    log.flush()


if __name__ == "__main__":
    main()
