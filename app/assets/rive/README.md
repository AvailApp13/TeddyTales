# Rive assets

`bear.riv` belongs here. It is not in git yet because the rig has not been
exported from the Rive Editor.

Export it from the Rive Editor as `bear.riv` and drop it in this directory:

    app/assets/rive/bear.riv

Then check it against the rig spec before wiring it into the app:

    cd tools && npm run lab     # open http://127.0.0.1:4321 -> "Load from repo"

The lab's Contract panel reports every name the app expects and whether the
file provides it. Green across the board means the Flutter side will bind.

`.riv` is a binary artifact. Keep it small (the whole point of choosing Rive)
and re-export rather than committing intermediate variants.
