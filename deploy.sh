#!/bin/bash
dub build -b release
scp xwing_math punkuser@xwing.gateofstorms.net:~/xwing_math/xwing_math_update
rsync -av public/ punkuser@xwing.gateofstorms.net:~/xwing_math/public/
