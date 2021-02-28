#!/bin/sh

java -jar files/runnable-texturepacker.jar files/ sheet/ sheet files/settings.json
./conv.d sheet/sheet.atlas > sheet/sheet
cp sheet/sheet.png assets
cp sheet/sheet assets
