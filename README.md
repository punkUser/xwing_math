# xwing_math
xwing_math is a tool for calculating dice probabilities and outcomes for
[X-Wing Miniatures](https://www.fantasyflightgames.com/en/products/x-wing/) by
[Fantasy Flight Games](https://www.fantasyflightgames.com/). The goal of the tool is to aid players in
list building, target selection and token spending by helping to develop intuition about the probabilities
of various outcomes.

The tool embeds a custom web server that serves as the user interface. A live version of the tool can be
viewed at http://xwing.gateofstorms.net/.

Development
-----------
xwing_math is written in the [D Programming Language](https://dlang.org/) and uses the [vibe.d](http://vibed.org/)
library to host the web interface. It currently supports Windows and Linux (Ubuntu and likely others).

Install the [D compiler](https://dlang.org/download.html) and [DUB](http://code.dlang.org/download) on your platform
of choice and build/run the application by invoking `dub` from the command line in the root directory.

Additional Setup on Linux
-------------------------
On Linux you may also need to install the dependencies for vibe.d. See the Linux section on
[this page](https://github.com/vibe-d/vibe.d) for more information.
