"""Redraw assets/titi/stop.png: the batch 2 render grew the arms out of the
front of the body. Same pipeline and look as tool/art_batch2.py.

  python tool/art_stop_fix.py      # two tries into tool/titi_gen/batch2/
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_batch2 as b2

ARMS = ("ARMS, follow strictly: exactly two short plush arms, one on each SIDE of the cone body, attached at shoulder height "
        "exactly like the thumbs-up reference; the arms are plain red-and-white plush like the body, no separate sleeves, "
        "nothing grows out of the front of the chest; the DRIVE SAFE sash stays diagonal across the front, unbroken. ")
STOP = [
    ARMS + "Pose: his RIGHT arm raised out to the side holding a small round red STOP sign on a short black handle beside his head, "
           "his LEFT mitten on his hip, serious but cute frown.",
    ARMS + "Pose: both arms reach forward from his sides holding a small round red STOP sign on a short black handle, the sign held low "
           "in front of his lower body so his face and the sash stay fully visible, serious but cute frown.",
]

if __name__ == '__main__':
    card = b2.upload(os.path.join(b2.REPO, 'assets/cards/c1.jpg'))
    good = b2.upload(os.path.join(b2.REPO, 'assets/titi/thumbsup.png'))
    jobs = {f'titi_stop_v{i + 1}': (b2.LOOK + p, [card, good], 'transparent', '1:1') for i, p in enumerate(STOP)}
    b2.run(jobs)
