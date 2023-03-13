# mame_xml_extractor
build a mame xml using only the  source files
extract and build a xml from source files, made for MAME 0.84 should work with previous versions<br>
script should generate a xml with samples, sampleof, bios and driver status information<br>
needs xidel and datutil in _bin\ folder, mamediff its optional to generate a report(changes from previous version) at the end<br>
a optional xml/dat file can be placed in sources\ to fill missing size,sha1 and get mamediff report<br>
script needs this folders from MAME source: vidhrdw\,sndhrdw\,drivers\ and driver.c under sources\src\<br>
the sourcefiles needs to be cleanse form uni-characters, using notepad++ "find in all files" with the regular expression "[^\x00-\x7F]+"<br>
script uses the "sort /unique" command, may be only available in windows 10<br>
https://www.videlibri.de/xidel.html<br>
http://www.logiqx.com/Tools/
