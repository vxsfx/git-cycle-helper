# GCH, Git Cycle Helper

## Command usage

=> gch startPreAlpha <major|minor>
Creates a new pre alpha branch.
Current Cycle must be release.
Fails when semantic type is patch.


=> gch startAlpha [preAlphaBranch]
Starts the alpha development cycle.
Creates an empty commit, and alpha tag.
When no branch specified starts from release.
If branch specified, merges pre-alpha first.

=> gch startBeta
Starts beta.
Current Cycle must be Alpha or Release.

=> gch startCandidate
Starts Release candidate.
Current Cycle must be beta.


=> gch startFeature <name>
Creates a feature branch.
Cannot create if Current development version is patch.
Cannot create if Current cycle is beta or candidate.

=> gch startPatch <name>
Creates patch branch.
