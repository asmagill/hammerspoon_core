hs.noises
=========

This version differs from core by running the `AudioQueueNewInput` callback on one of the audio queue’s internal threads rather than on the Hammerspoon primary queue.  This offloads the evaluation from the primary queue and seems to be somewhat more responsive when the machine is under load.

