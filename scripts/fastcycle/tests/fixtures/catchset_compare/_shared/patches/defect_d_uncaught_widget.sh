#!/bin/sh
# SeededDefect D_uncaught: drops NO marker output (a purely cosmetic change --
# this comment line itself), so no toy gate in this fixture set can detect
# it. Used by cs_negctrl_old_missed to model "a defect neither config
# catches". All three runtime-output tokens (space-separated form, per
# widget.sh's §11.4.273 convention) remain byte-identical to the clean
# baseline.
echo "SAFE MARKER"
echo "OTHER MARKER"
echo "EXTRA MARKER"
exit 0
