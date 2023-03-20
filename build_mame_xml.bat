@echo off
rem //extract and build a xml from source files, made for MAME 0.84 should work with previous versions
rem //script should generate a xml with samples, sampleof, bios and driver status information
rem //needs xidel and datutil in _bin\ folder, mamediff its optional to generate a report(changes from previous version) at the end
rem //a optional xml/dat file can be placed in sources\ to fill missing size,sha1 and get mamediff report
rem //script needs this folders from MAME source: vidhrdw\,sndhrdw\,drivers\ and driver.c under sources\src\
rem //the sourcefiles needs to be cleanse form uni-characters, using notepad++ "find in all files" with the regular expression "[^\x00-\x7F]+"
rem //script uses the "sort /unique" command, may be only available in windows 10
rem //https://www.videlibri.de/xidel.html
rem //http://www.logiqx.com/Tools/

title MAMEoXtras xml builder [Build: Mar-16-2023]
setlocal enabledelayedexpansion

set _error=0
if not exist sources set _error=1
if not exist sources\src set _error=1
if not exist sources\src\driver.c set _error=1
if not exist sources\src\vidhrdw set _error=1
if not exist sources\src\sndhrdw set _error=1
if not exist sources\src\drivers set _error=1
if not exist _bin set _error=2
if not exist _bin\xidel.exe set _error=2
if not exist _bin\datutil.exe set _error=2

if %_error%==1 (
	title ERROR&echo no MAME sources were found. place drivers,vidhrdw,drivers and driver.c inside sources\src folder
	md sources & md sources\src
	pause&exit
)

if %_error%==2 (
	title ERROR&echo This scrip needs xidel and datutil inside _bin\
	md _bin
	pause&exit
)
echo:
echo *************************************************************
echo * Make sure to remove uni characters from MAME src files    *
echo * uning Notepad++ and the regex expression "[^\x00-\x7F]+"  *
echo *                                                           *
echo *************************************************************
echo:
timeout 10 & cls

set /a "_time0=%time:~0,2%*3600+%time:~3,1%*600+%time:~4,1%*60+%time:~6,1%*10+%time:~7,1%"
if not exist _temp (md _temp)else (del /q /s _temp >nul)

rem // drivers with duplicated games in MAMEoXtras
if exist sources\src\drivers\digdug.c (
	if exist sources\src\drivers\galaga.c (
		for %%g in (digdug.c bosco.c xevious.c locomotn.c afega.c) do ren sources\src\drivers\%%g %%~ng.bak 
	)
)

cls&title Building drivers.c ...
for %%g in (sources\src\drivers\*.c,sources\src\sndhrdw\*.c,sources\src\vidhrdw\*.c,sources\src\drivers\*.h,sources\src\sndhrdw\*.h,sources\src\vidhrdw\*.h) do (
	echo %%~nxg
	(echo -------------------------------------------------- %%g --------------------------------------------------------------------) >>_temp\drivers.c
	type "%%g" >>_temp\drivers.c
)

call :clean_file drivers.c 1

rem //find and extract bios list
_bin\xidel -s "_temp\drivers.c" -e "extract( $raw, '^[\t ]*GAMEB?X? ?\([\t\d?+ ]+,[\t ]*(\w+)[\t ]*,.+?NOT_A_DRIVER.+', 1, 'm*')" >_temp\bios.lst

rem //extract games index from from driver.c, bios not included
copy /y sources\src\driver.c _temp >nul
call :clean_file driver.c 1
_bin\xidel -s _temp\driver.c -e "extract( $raw, '^[\t ]*DRIVER ?\([ \t]*(\w+)[ \t]*\)', 1, '*m')" >_temp\main.lst
type _temp\bios.lst >>_temp\main.lst

REM ****** line counter ************
set _total_lines=0
set _count_lines=0
for %%g in (sources\src\drivers\*.c) do set /a "_total_lines+=1"
if %_total_lines%==0 (
	title ERROR&echo "sources\src\drivers" folder its empty
	pause & exit
)

rem //go trough all src drivers files and extract game rom information, takes ~40min
cls&title Building mame.c...
del _temp\mame.log & type nul>_temp\mame.c
for %%g in (sources\src\drivers\*.c) do (
	echo %%~nxg
	copy /y "%%g" _temp\driver.c >nul
	call :clean_file driver.c
	
	_bin\xidel -s _temp\driver.c -e "replace( $raw, '^[\t ]*GAMEX? ?\([\t ]*([\d?+]+)[\t ]*,[\t ]*(\w+)[\t ]*,[\t ]*(\w+)[\t ]*,[\t ]*(\w+)[\t ]*,[\t\w ]+,[\t\w ]+,[\t\w|^ ]+,[\t ]*\""(.+?)\""[\t ]*,[\t ]*\""(.+?)\""[\t ]*(?:,([()?:\t |A-Z0_]+))?\)', '<game name=\"$2\" sourcefile=\""%%~nxg\"" cloneof=\""$3\"" romof=\""$3\"" machine=\""$4\"">[LF]<description>$6</description>[LF]<year>$1</year>[LF]<manufacturer>$5</manufacturer>[LF]<flags>$7</flags>[LF]<machine>$4</machine>', 'm')" >_temp\games.1
	
	for /f %%h in ('_bin\xidel -s _temp\driver.c -e "matches( $raw, '^[\t ]*GAMEBX?', 'm')"') do if %%h==true ( 
		_bin\xidel -s _temp\games.1 -e "replace( $raw, '^[\t ]*GAMEBX? ?\([\t ]*([\d?+]+)[\t ]*,[\t ]*(\w+)[\t ]*,[\t ]*(\w+)[\t ]*,[\t ]*(\w+)[\t ]*,[\t ]*(\w+)[\t ]*,[\t\w ]+,[\t\w ]+,[\t\w|^ ]+,[\t ]*\""(.+?)\""[\t ]*,[\t ]*\""(.+?)\""[\t ]*(?:,([()?:\t |A-Z0_]+))?\)', '<game name=\""$2\"" sourcefile=\""%%~nxg\"" cloneof=\""$3\"" romof=\""$4\"" machine=\""$5\"">[LF]<description>$7</description>[LF]<year>$1</year>[LF]<manufacturer>$6</manufacturer>[LF]<flags>$8</flags>[LF]<machine>$5</machine>[LF]<romof>$4</romof>', 'm')" >_temp\temp.1
		del _temp\games.1 & ren _temp\temp.1 games.1
	)
	call :build_mame "%%~xng"
)

cls&title extracting BIOS code...

rem //cleanup
_bin\xidel -s _temp\mame.c -e "replace( $raw, '\[LF\]', codepoints-to-string((13,10)))" >_temp\temp.1
del _temp\mame.c & ren _temp\temp.1 mame.c

rem //get and add bios code block
for /f %%g in (_temp\bios.lst) do (
	echo %%g
	_bin\xidel -s _temp\drivers.c -e "extract( $raw, '^[\t ]*ROM_START\([\t ]*%%g[\t ]*\)\s+(.+?)ROM_END', 1, 'ms')" >_temp\temp.1
	
	_bin\xidel -s _temp\mame.c -e "replace( $raw, '^<romof>%%g</romof>', file:read-text('_temp\temp.1'), 'm')" >_temp\temp.2
	_bin\xidel -s _temp\temp.2 -e "replace( $raw, ' cloneof=\""%%g\""', '')" >_temp\temp.1
	_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^<game name=\""%%g\""', '<game isbios=\""yes\"" name=\""%%g\""', 'm')" >_temp\mame.c
)

cls&title extracting and replacing macros...

rem //get and add functions code block
_bin\xidel -s _temp\mame.c -e "extract( $raw, '^[\t ]*([A-Z_0-9]+)[\t ]*$', 1, 'm*')" >_temp\index.1
sort /unique _temp\index.1 /o _temp\index.1

for /f %%g in (_temp\index.1) do (
	echo %%g	
	_bin\xidel -s _temp\drivers.c -e "extract( $raw, '^[\t ]*#define[\t ]+%%g(.+?)^\s+$', 1, 'sm')" >_temp\temp.1
	_bin\xidel -s _temp\temp.1 -e "replace( $raw, '[\\]', '')" >_temp\temp.2
	
	_bin\xidel -s _temp\mame.c -e "replace( $raw, '^[\t ]*%%g[\t ]*$', file:read-text('_temp\temp.2'), 'm')" >_temp\temp.1
	del _temp\mame.c & ren _temp\temp.1 mame.c
)

cls
rem //get and replaces macros *********
_bin\xidel -s _temp\drivers.c -e "extract( $raw, '^[\t ]*([A-Zx\d_]+)[\t ]*\([\d\t, ]*\""([\w\s&#=.-]+)\""[\t ]*,', 1, 'm*')" >_temp\temp.1
sort /unique _temp\temp.1 /o _temp\index.1
del _temp\define.xml 2>nul
for /f %%g in (_temp\index.1) do (
	for /f %%h in ('_bin\xidel -s _temp\drivers.c -e "matches( $raw, '^[\t ]*#define[\t ]+%%g.+', 'm')"') do if %%h==true (
		echo %%g
		(echo ^<game name="%%g"^>
		_bin\xidel -s _temp\drivers.c -e "extract( $raw, '^[\t ]*#define[\t ]+%%g(.+?)^\s+$', 1, 'sm')"
		echo ^</game^>) >>_temp\define.xml
	)
)
_bin\xidel -s _temp\define.xml -e "replace( $raw, '[\\]', '')" >_temp\temp.1
del _temp\define.xml & ren _temp\temp.1 define.xml


rem //get and add BIOS functions code block (seems that its not needed)
REM _bin\xidel -s _temp\define.xml -e "extract( $raw, '^[\t ]*([A-Z_0-9]+)[\t ]*$', 1, 'm*')" >_temp\index.1
REM sort /unique _temp\index.1 /o _temp\index.1
REM for /f %%g in (_temp\index.1) do (
	REM echo %%g	
	REM _bin\xidel -s _temp\drivers.c -e "extract( $raw, '^[\t ]*#define[\t ]+%%g(.+?)^\s+$', 1, 'sm')" >_temp\temp.1
	REM _bin\xidel -s _temp\temp.1 -e "replace( $raw, '[\\]', '')" >_temp\temp.2
	
	REM _bin\xidel -s _temp\define.xml -e "replace( $raw, '^[\t ]*%%g[\t ]*$', file:read-text('_temp\temp.2'), 'm')" >_temp\temp.1
	REM del _temp\define.xml & ren _temp\temp.1 define.xml
REM )

rem //convert to xml
_bin\xidel -s _temp\define.xml -e "replace( $raw, '^[\t ]*ROM_LOAD[A-Z_\d]*\([a-z\s]+,[\w)(\s+]+,[\t ]*([\dXx]+)[\t ]*,[a-z\s]+\).*', '<cont size=\""$1\""/>', 'm')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "extract( $raw, '^(<.+?>)', 1, 'm*')" >_temp\romload.xml

REM _bin\xidel -s _temp\define.xml -e  "replace( $raw, '^[\t ]*ROM_LOAD[\dA-Z_]*[\t ]*\([\d\t, ]*\""([\w\s&#=.-]+)\""[\t ]*,[\w\s+*]+(?:,[\t ]*([\w+*]+)[\t ]*)?,[\t ]*CRC\((\w{8})\)[\t ]*(?:SHA1\((\w{40})\))?.+', '<rom name=\""$1\"" size=\""$2\"" crc=\""$3\"" sha1=\""$4\""/>', 'm')" >_temp\temp.1
REM _bin\xidel -s _temp\temp.1 -e "extract( $raw, '^(<.+?>)', 1, 'm*')" >_temp\rom.xml

cls
rem //replace macros code block into mame.c
for /f %%g in ('_bin\xidel -s _temp\romload.xml -e "//game[rom or cont]/@name"') do (
	for /f %%h in ('_bin\xidel -s _temp\mame.c -e "matches( $raw, '^[\t ]*%%g[\t ]*\(.+', 'm')"') do (
		echo %%g
		_bin\xidel -s _temp\romload.xml -e "extract( $raw, '^<game name=\""%%g\"">\s+(.+?)</game>', 1, 'sm')" >_temp\temp.1
	
		_bin\xidel -s _temp\mame.c -e "replace( $raw, '^([\t ]*%%g[\t ]*\(.+?(\r\n))', '$1	<macro name=\""%%g\""/>$2', 'm')" >_temp\temp.2
		_bin\xidel -s _temp\temp.2 -e "replace( $raw, '<macro name=\""%%g\""/>', file:read-text('_temp\temp.1'))" >_temp\mame.c
	)
)

rem //clean emtpy lines
_bin\xidel -s _temp\mame.c -e "replace( $raw, '^\s+$', '', 'm')" >_temp\temp.1
del _temp\mame.c & ren _temp\temp.1 mame.c

rem \\ ****************** SAMPLES ***************************
rem \\ extracting sampleof information was too complicated. required to find the machine related to the game, and work backwards to find
rem \\ the correct sample array, moreover, some arrays are defined as global variables? theres not a direct way to extract sampleof.
rem \\ however, extracting sample array its easy, and should be enough to have the correct samples. 

cls&title extracting and replacing samples...
rem //extract samples array and make samples array list
_bin\xidel -s _temp\drivers.c -e "extract( $raw, '^(?:static )?const char \*\w*sample_names\w*\[\][\t ]*=\s+\{.+?\}[\t ]*;', 0, 'ms*')" >_temp\samples.c

rem //convert samples.c to xml, use <array tag to save array name
_bin\xidel -s _temp\samples.c -e "replace( $raw, '\"([-\w\s]+)(?:\.wav)?\"', '<sample name=\"$1.wav\"/>', 'i')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^(?:static )?const char \*(\w*sample_names\w*)\[\].+', '<game name=\"$1\">', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '\"\*(\w+)\"', '<array name=\"$1\"/>')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^[\t ]*\}[\t ]*;', '</game>', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "extract( $raw, '(<.+?>)', 1, '*')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^(<(?:sample|array) )', '	$1', 'm')" >_temp\samples.xml

rem //get all games names with array and samples
_bin\xidel -s _temp\samples.xml -e "//game[array and sample]/array/(../@name|@name)" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^(\w+)\r\n(\w+)$', '$1	$2', 'm')" >_temp\sampleof.equ

rem //get all games with no array and have samples and point to the game (spaceod)
_bin\xidel -s _temp\samples.xml -e "//game[not(array) and sample]/@name" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^((\w+)_sample_names)$', '$1	$2', 'm')" >>_temp\sampleof.equ

rem // extract all machine driver code blocks
_bin\xidel -s _temp\drivers.c -e "extract( $raw, '^(?:static )?MACHINE_DRIVER_START.+?MACHINE_DRIVER_END', 0, '*sm')" >_temp\machine.c

rem //convert machine.c to xml for easy extraction
_bin\xidel -s _temp\machine.c -e "replace( $raw, '^[\t ]*(?:static )?MACHINE_DRIVER_START\([\t ]*(\w+)[\t ]*\).*', '<machine name=\""$1\"">', 'm')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^[\t ]*MDRV_SOUND_ADD\(SAMPLES,[\t ]*(\w+)[\t ]*\).*', '	<samples name=\""$1\""/>', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^[\t ]*MDRV_SOUND_ADD_TAG\(\""samples?\"",[\t ]*SAMPLES[\t ]*,[\t ]*(\w+)[\t ]*\).*', '	<samples name=\""$1\""/>', 'm')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^[\t ]*MDRV_SOUND_REPLACE\(\""samples?\"",[\t ]*SAMPLES[\t ]*,[\t ]*(\w+)[\t ]*\).*', '	<replace name=\""$1\""/>', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^[\t ]*MDRV_SOUND_REMOVE\(\""samples?\""\).*', '	<remove name=\""samples\""/>', 'm')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^[\t ]*MDRV_IMPORT_FROM\([\t ]*(\w+)[\t ]*\).*', '	<import name=\""$1\""/>', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^[\t ]*MACHINE_DRIVER_END.*', '</machine>', 'm')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "extract( $raw, '^\t?<.+', 0, '*m')" >_temp\machine.xml

rem //replace generic "samples_interface" with game machine name to follow after import
_bin\xidel -s _temp\machine.xml -e "//machine[samples and not(remove)]/samples[@name='samples_interface']/../@name" >_temp\index.1
for /f %%g in (_temp\index.1) do (
	echo %%g
	_bin\xidel -s _temp\machine.xml -e "extract( $raw, '^<machine name=\""%%g\"">.+?</machine>', 0, 'sm')" >_temp\temp.1
	_bin\xidel -s _temp\temp.1 -e "replace( $raw, '<samples name=\""samples_interface\""/>', '<samples name=\""%%g_samples_interface_notfound\""/>')" >_temp\temp.2
	
	_bin\xidel -s _temp\machine.xml -e "replace( $raw, '^<machine name=\""%%g\"">.+?</machine>', file:read-text('_temp\temp.2'), 'sm')" >_temp\temp.1
	del _temp\machine.xml & ren _temp\temp.1 machine.xml
)

rem //simulate "import functions"
call :import_machine

rem //get all machines with sample interface, start building "samples.equ" (machine,array,sampleof)
_bin\xidel -s _temp\machine.xml -e "//machine[samples and not(remove)]/samples/(../@name|@name)" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^(\w+)\r\n(\w+)$','$1	$2', 'm')" >_temp\samples.equ

cls
rem //simulate "replacement function"
_bin\xidel -s _temp\machine.xml -e "//machine/replace/(../@name|@name)" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^(\w+)\r\n(\w+)$','$1	$2', 'm')" >_temp\index.1
for /f "tokens=1,2" %%g in (_temp\index.1) do (
	echo %%g ---^> %%h
	_bin\xidel -s _temp\samples.equ -e "replace( $raw, '^%%g\t\w+', '%%g	%%h', 'm')" >_temp\temp.1
	del _temp\samples.equ & ren _temp\temp.1 samples.equ
)

rem //get sample_interface to sample_names relationships
_bin\xidel -s _temp\drivers.c -e "extract( $raw, '^(?:static )?struct Samplesinterface \w*samples_interface\w* =\s+\{.+?\};', 0, 'mis*')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^(?:static )?struct Samplesinterface (\w*samples_interface\w*) =.*', '<machine name=\""$1\"">', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^[\t ]*(\w*sample_names\w*)', '	<samples name=\""$1\""/>', 'm')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^[\t ]*\}[\t ]*;', '</machine>', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "extract( $raw, '^\t?<.+', 0, '*m')" >_temp\inter.xml

rem //rename generic array name "sample_names" to game not found
_bin\xidel -s _temp\inter.xml -e "//machine[samples]/samples/(../@name|@name)" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^(\w+)\r\n(\w+)$','$1	$2', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^((\w+)_samples_interface)\tsample_names$', '$1	$2_sample_names_notfound', 'm')" >_temp\inter.equ

cls
rem //combine inter.equ with samples.equ
for /f "tokens=1,2" %%g in (_temp\inter.equ) do (
	echo %%g ----^> %%h
	_bin\xidel -s _temp\samples.equ -e "replace( $raw, '^(\w+)\t%%g$', '$1	%%h', 'm')" >_temp\temp.1
	del _temp\samples.equ & ren _temp\temp.1 samples.equ
)

cls
rem //combine sampleof.equ and samples.equ and seach "assumed" sample_name for not found arrays
for /f "tokens=1,2" %%g in (_temp\sampleof.equ) do (
	echo %%g -----^> %%h
	for /f %%i in ('_bin\xidel -s _temp\samples.equ -e "matches( $raw, '\t%%g$', 'm')"') do if %%i==true (
		_bin\xidel -s _temp\samples.equ -e "replace( $raw, '(\t%%g)$', '$1	%%h', 'm')" >_temp\temp.1
		del _temp\samples.equ & ren _temp\temp.1 samples.equ
	)else (
		call :find_samples %%g %%h
	)
)
rem //mark notfound arrays
_bin\xidel -s _temp\samples.equ -e "replace( $raw, '^(\w+\t\w+)$', '$1	notfound', 'm')" >_temp\temp.1
del _temp\samples.equ & ren _temp\temp.1 samples.equ

cls
rem //delete previous entry and get all games with global "sample_names" and extract all games related to their sourcefile and machine name
for /f %%g in ('_bin\xidel -s _temp\samples.xml -e "//game[@name='sample_names']"/array/@name') do (
	for /f %%h in ('_bin\xidel -s _temp\mame.c -e "extract( $raw, '^<game name=\""%%g\"" sourcefile=\""([\w.]+)\""', 1, 'm')"') do (
		for /f %%i in ('_bin\xidel -s _temp\mame.c -e "extract( $raw, '^<game name=\""\w+\"" sourcefile=\""%%h\"".+?machine=\""(\w+)\"">', (1,2), '*m')"') do (
			(echo %%i	%%g	%%g) >>_temp\samples.equ
		)
	)
)
sort /unique _temp\samples.equ /o _temp\samples.equ

rem //delete lines with sampleof notfound, this will be games not linked to an array, make a backup for reference
copy /y _temp\samples.equ _temp\samples.equ.bak
_bin\xidel -s _temp\samples.equ -e "replace( $raw, '^.+\tnotfound$', '', 'm')" >_temp\temp.1
del _temp\samples.equ & ren _temp\temp.1 samples.equ

cls
rem //replace samples in mame.xml
for /f "tokens=1,2,3" %%g in (_temp\samples.equ) do (
	echo %%g ----^> %%i
	for /f %%j in ('_bin\xidel -s _temp\samples.xml -e "matches( $raw, '<game name=\""%%h\"">')"') do if %%j==true (
		call :replace_array %%g %%h %%i game
	)else (
		for /f %%k in ('_bin\xidel -s _temp\samples.xml -e "matches( $raw, '<array name=\""%%h\""/>')"') do if %%k==true (
			call :replace_array %%g %%h %%i array
		)else (echo %%g	%%h NOT_FOUND Samples) >>_temp\mame.log	
	) 
)

rem // ***************** END OF SAMPLES **********************************************

cls&title transforming mame.c to xml...
rem //convert to xml
_bin\xidel -s _temp\mame.c -e "replace( $raw, '^[\t ]*DISK_IMAGE(?:_READONLY)?\( \"(\w+)\",[\d ]+, BAD_DUMP MD5\((\w+)\) SHA1\((\w+)\).+', '<disk name=\""$1\"" size=\""\"" sha1=\""$3\"" md5=\""$2\"" status=\""baddump\""/>', 'm')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^[\t ]*DISK_IMAGE(?:_READONLY)?\( \"(\w+)\",[\d ]+, NO_DUMP(?: MD5\((\w+)\) SHA1\((\w+)\))?.+', '<disk name=\""$1\"" size=\""\"" sha1=\""$3\"" md5=\""$2\"" status=\""nodump\""/>', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^[\t ]*DISK_IMAGE(?:_READONLY)?\( \"(\w+)\",[\d ]+, MD5\((\w+)\) SHA1\((\w+)\).+', '<disk name=\""$1\"" size=\""\"" sha1=\""$3\"" md5=\""$2\""/>', 'm')" >_temp\temp.1

_bin\xidel -s _temp\temp.1 -e  "replace( $raw, '^[\t ]*[A-Zx\d_]+[\t ]*\([\d\t, ]*\""([\w\s&#=.-]+)\""[\t ]*(?:,[\w\s*+]+|,[\w\s*+]+,[\t ]*([\w+*]+)[\t ]*)?,[\t ]*NO_DUMP[\t ]*CRC\((\w{8})\)[\t ]*(?:SHA1\((\w{40})\))?.+', '<rom name=\""$1\"" size=\""$2\"" crc=\""$3\"" sha1=\""$4\"" status=\""nodump\""/>', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e  "replace( $raw, '^[\t ]*[A-Zx\d_]+[\t ]*\([\d\t, ]*\""([\w\s&#=.-]+)\""[\t ]*(?:,[\w\s*+]+|,[\w\s*+]+,[\t ]*([\w+*]+)[\t ]*)?,[\t ]*NO_DUMP.+', '<rom name=\""$1\"" size=\""$2\"" crc=\""\"" sha1=\""\"" status=\""nodump\""/>', 'm')" >_temp\temp.1

_bin\xidel -s _temp\temp.1 -e  "replace( $raw, '^[\t ]*[A-Zx\d_]+[\t ]*\([\d\t, ]*\""([\w\s&#=.-]+)\""[\t ]*(?:,[\w\s*+]+|,[\w\s*+]+,[\t ]*([\w+*]+)[\t ]*)?,[\t ]*BAD_DUMP[\t ]*CRC\((\w{8})\)[\t ]*(?:SHA1\((\w{40})\))?.+', '<rom name=\""$1\"" size=\""$2\"" crc=\""$3\"" sha1=\""$4\"" status=\""baddump\""/>', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e  "replace( $raw, '^[\t ]*[A-Zx\d_]+[\t ]*\([\d\t, ]*\""([\w\s&#=.-]+)\""[\t ]*(?:,[\w\s*+]+|,[\w\s+*]+,[\t ]*([\w+*]+)[\t ]*)?,[\t ]*CRC\((\w{8})\)[\t ]*(?:SHA1\((\w{40})\))?.+', '<rom name=\""$1\"" size=\""$2\"" crc=\""$3\"" sha1=\""$4\""/>', 'm')" >_temp\temp.1

_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^[\t ]*ROM_CONTINUE[\t ]*\([\w\s*+]+,[\t ]*([\w*+]+)[\t ]*\).*', '<cont size=\""$1\""/>', 'm')" >_temp\temp.2
rem //need this to prevent adding extra sizes to rom
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^[\t ]*ROM_RELOAD[\t ]*\(.+', '<reload/>', 'm')" >_temp\mame.c

rem //will close datafile at the end of script, start building mame.xml
(echo ^<?xml version="1.0"?^>
echo ^<datafile^>
_bin\xidel -s _temp\mame.c -e "extract( $raw, '^[\t ]*<.+', 0, 'm*')")>_temp\mame.xml

rem //replace empty size entries
_bin\xidel -s _temp\mame.xml -e "replace( $raw, 'size=\"\"', 'size=\"0\"')" >_temp\temp.1
del _temp\mame.xml & ren _temp\temp.1 mame.xml

rem // add rom continue size to final rom size
call :add_size

rem //remove trailing spaces in flags tag for easy matching
_bin\xidel -s _temp\mame.xml -e "replace( $raw, '<flags>[\t ]*(.+?)[\t ]*</flags>', '<flags>$1</flags>')" >_temp\temp.1
del _temp\mame.xml & ren _temp\temp.1 mame.xml

rem //convert driver flags to xml 
call :get_flags

rem //fill in missing size and sha1 information from another datafile, (optional)
for %%g in (sources\*.dat,sources\*.xml) do set "_datafile=%%g"
if not "%_datafile%"=="" (
	cls&title Adding extra size and sha1 info....
	_bin\xidel -s _temp\mame.xml -e "extract( $raw, 'crc=\""(\w{8})\"" sha1=\""0?\""', 1, '*')" >_temp\sha1.lst
	_bin\xidel -s _temp\mame.xml -e "extract( $raw, 'size=\""0?\"" crc=\""(\w{8})\""', 1, '*')" >_temp\size.lst

	sort /unique _temp\sha1.lst /o _temp\sha1.lst
	sort /unique _temp\size.lst /o _temp\size.lst

	for /f %%g in (_temp\size.lst) do (
		for /f %%h in ('_bin\xidel -s "%_datafile%" -e "extract( $raw, 'size=\""(\d+)\"" crc=\""%%g\""', 1, 'i')"') do (
			echo %%g ---^> %%h
			_bin\xidel -s _temp\mame.xml -e "replace( $raw, 'size=\""0?\""( crc=\""%%g\"")', 'size=\""%%h\""$1', 'i')" >_temp\temp.1
			del _temp\mame.xml & ren _temp\temp.1 mame.xml
		)
	)
	for /f %%g in (_temp\sha1.lst) do (
		for /f %%h in ('_bin\xidel -s "%_datafile%" -e "extract( $raw, 'crc=\""%%g\"" sha1=\""([a-f\d]{40})\""', 1, 'i')"') do (
			echo %%g ---^> %%h
			_bin\xidel -s _temp\mame.xml -e "replace( $raw, '(crc=\""%%g\"" )sha1=\""0?\""', '$1sha1=\""%%h\""', 'i')" >_temp\temp.1
			del _temp\mame.xml & ren _temp\temp.1 mame.xml
		)
	)
)
cls&title Cleaning mame.xml...
rem //cleanup
_bin\xidel -s _temp\mame.xml -e "replace( $raw, ' cloneof=\""0\""| romof=\""0\""', '')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '<unknown>', 'unknown')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '></', '>unknown</')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, ' machine=\""\w+\""', '')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^<machine>\w+</machine>\s+', '', 'm')" >_temp\temp.1

_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^<reload/>\s+', '', 'm')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^<cont size=\""\d+\""/>\s+', '', 'm')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '[&]', '&amp;')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^[\t ]*<array name=\""\w+\""/>\r\n', '', 'm')" >_temp\mame.xml

cls
rem //remove sampleof its self
for /f %%g in ('_bin\xidel -s _temp\samples.equ -e "extract( $raw, '\t(\w+)$', 1, 'm*')"') do (
	echo %%g
	_bin\xidel -s _temp\mame.xml -e "replace( $raw, '^(<game name=\""%%g\"".+?) sampleof=\""%%g\""', '$1', 'm')" >_temp\temp.1
	del _temp\mame.xml & ren _temp\temp.1 mame.xml
)

rem //correct romof bios for clones, and romof bios for bios
_bin\xidel -s _temp\mame.xml -e "replace( $raw, 'cloneof=\""(\w+)\"" romof=\""\w+\""', 'cloneof=\""$1\"" romof=\""$1\""')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^(<game isbios=\""yes\"" name=\""\w+\"" sourcefile=\""[\w.]+\"") romof=\""\w+\"">', '$1>', 'm')" >_temp\mame.xml

rem //xevious samples cannot be completed in romcenter since battles coloneof xevious its set to use its own samples, game dosent boot anyway
_bin\xidel -s _temp\mame.xml -e "replace( $raw, 'romof=\""xevious\"">$', 'romof=\""xevious\"" sampleof=\""xevious\"">', 'm')" >_temp\temp.1
del _temp\mame.xml & ren _temp\temp.1 mame.xml

rem //cleanup empty lines
_bin\xidel -s _temp\mame.xml -e "replace( $raw, '^\s+$', '', 'm')" >_temp\temp.1
del _temp\mame.xml & ren _temp\temp.1 mame.xml

rem //look for sampleof with no game, and add a ghost game so datutil will keep sampleof
_bin\xidel -s _temp\mame.xml -e "extract( $raw, 'sampleof=\""(\w+)\""', 1, '*')" >_temp\index.1
sort /unique _temp\index.1 /o _temp\index.1

for /f %%g in (_temp\index.1) do (
	for /f %%h in ('_bin\xidel -s _temp\mame.xml -e "matches( $raw, '<game name=\""%%g\""')"') do if %%h==false (
		for /f %%i in ('_bin\xidel -s _temp\mame.xml -e "extract( $raw, 'sourcefile=\""([\w.]+)\"".+?sampleof=\""%%g\""', 1)"') do (
			(echo ^<game name="%%g" sourcefile="%%i"^>) >>_temp\mame.xml
		) 
	
		(echo ^<description^>%%g Samples^</description^>
		echo ^<year^>????^</year^>
		echo ^<manufacturer^>unknown^</manufacturer^>) >>_temp\mame.xml
		
		_bin\xidel -s _temp\mame.xml -e "extract( $raw, 'sampleof=\""%%g\"">(.+?)</game>', 1, 's')" >_temp\temp.1
		_bin\xidel -s _temp\temp.1 -e "extract( $raw, '<sample name=\""[-\w\s.]+\""/>', 0, '*')" >>_temp\mame.xml
		
		(echo ^<driver status="good" emulation="good" color="good" sound="good" graphic="good"/^>
		echo ^</game^>) >>_temp\mame.xml

	) 
)

rem //add full invaders samples (invad2ct,astinvad)
_bin\xidel -s _temp\mame.xml -e "extract( $raw, '^<game name=\""invaders\"" sourcefile=\""[\w.]+\"">.+?</game>', 0, 'sm')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^\t?<sample name=\""[\w.]+\""/>\r\n|</game>', '', 'm')" >_temp\invaders.1
(for /l %%g in (0,1,18) do echo ^<sample name="%%g.wav"/^>
echo ^</game^>) >>_temp\invaders.1

_bin\xidel -s _temp\mame.xml -e "replace( $raw, '^<game name=\""invaders\"" sourcefile=\""[\w.]+\"">.+?</game>', '', 'sm')" >_temp\temp.1
del _temp\mame.xml & ren _temp\temp.1 mame.xml
type _temp\invaders.1 >>_temp\mame.xml

rem //close datafile
(echo ^</datafile^>) >>_temp\mame.xml


rem // output
md output 2>nul

for /f "tokens=%date:~4,2%" %%g in ("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec") do set _month=%%g
set "_file=MAMEoXtras_[%_month%-%date:~7,2%-%date:~10,4%].xml"

rem // sort roms, keep as much information, verbose loging, convert to lower case 
_bin\datutil -s -k -v -l -f listxml -o "output\%_file%" _temp\mame.xml
move /y datutil.log output\

_bin\datutil -f gamelist -o output\gamelist.txt "output\%_file%"
_bin\datutil -f titles -o output\titles.txt "output\%_file%"
del datutil.log

rem // make romstatus.xml for mameoxtras using the created new xml
rem // 4=outof memory, 2=runs slowly, 1=working, 3=crashes, 5=general nonworking, empty=unknown

rem //option 1, use crahes for prelimnary status, and general nonworking for imperfect status games?
rem //option 2, use crashes for emulation="preliminary", and general nonworking for protection,sound,graphics,color="preliminary", imperfect will be ignored. assume alltoer games 'good'


cls&title Building romstatus.xml...
rem //remove this becuase xidel breaks
_bin\xidel -s "output\%_file%" -e "replace( $raw, '^<\WDOCTYPE mame \[.+?\]>', '', 'sm')" >_temp\datafile.1

_bin\xidel -s _temp\datafile.1 -e "//game[driver]/driver[@emulation='preliminary']/../@name" >_temp\crashes.lst
_bin\xidel -s _temp\datafile.1 -e "//game[driver]/driver[@color='preliminary' or @sound='preliminary' or @graphic='preliminary' or @protection='preliminary']/../@name" >_temp\nonworking.lst

rem //cusotm list of games and drivers that run slowly in mameoxtras
call :get_custom

del _temp\slowly.lst 2>nul
for /f %%g in (_temp\custom.lst) do (
	for /f %%h in ('_bin\xidel -s _temp\datafile.1 -e "matches( $raw, 'sourcefile=\""%%g\""', 'q')"') do if %%h==true (
		_bin\xidel -s _temp\datafile.1 -e "//game[@sourcefile='%%g']/@name" >>_temp\slowly.lst
		
	)else (
		(echo %%g) >>_temp\slowly.lst
	)
)

rem //adding games that required chd to slowly.lst
_bin\xidel -s _temp\datafile.1 -e "//game[disk]/@name" >>_temp\slowly.lst

rem //get all games that have roms exept bios
_bin\xidel -s _temp\datafile.1 -e "//game[not(@isbios) and rom]/@name" >_temp\index.1

(echo ^<^^!-- RomStatus XML / MAMEoXtras / %_file% --^>
echo ^<Roms^>) >_temp\romstatus.xml
for /f %%g in (_temp\index.1) do (
	call :build_romstatus %%g

)
(echo ^</Roms^>) >>_temp\romstatus.xml

move /y _temp\romstatus.xml output\

rem //rebuild catver.ini and add new games, if sources\catver.ini its found
if exist sources\catver.ini (
	cls&title Building catver.ini...
	
	(echo ;;  catver.ini / %_file% / MAMEoXTras ;;
	echo:
	echo [Category]) >_temp\catver.ini
	
	_bin\xidel -s --input-format=html sources\catver.ini -e "extract( $raw, '^\w+=[A-Za-z].+', '0', 'm*')" >_temp\catver.1
	
	_bin\xidel -s _temp\datafile.1 -e "//game[@cloneof]/(@name|@cloneof)" >_temp\temp.1
	_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^(\w+)\r\n(\w+)', '$1	$2', 'm')" >_temp\cloneof.1
	_bin\xidel -s _temp\datafile.1 -e "//game[not(@cloneof) and not(@isbios) and rom]/@name" >>_temp\cloneof.1

	sort _temp\cloneof.1 /o _temp\cloneof.1
	
	rem //all games that have roms exept bios
	for /f "tokens=1,2" %%g in (_temp\cloneof.1) do (
		
		>nul 2>&1 findstr /b "%%g=" _temp\catver.1
		if !errorlevel!==0 (
			echo %%g
			findstr /b "%%g=" _temp\catver.1 >>_temp\catver.ini
		)else (
			call :build_catver %%g %%h
		)
	)
)
move /y _temp\catver.ini output\

cls&title Making suplemental batch scripts...
rem //make individual batch script for easy rom organization

rem //clones, bios, parents
_bin\xidel -s _temp\datafile.1 -e "//game[@isbios]/@name" >_temp\bios.lst
_bin\xidel -s _temp\datafile.1 -e "//game[@cloneof]/@name" >_temp\clones.lst
_bin\xidel -s _temp\datafile.1 -e "//game[not(@cloneof) and not(@isbios) and rom]/@name" >_temp\parents.lst

rem //overall status
REM _bin\xidel -s _temp\datafile.1 -e "//game[driver]/driver[@status='preliminary']" >_temp\preliminary.lst
REM _bin\xidel -s _temp\datafile.1 -e "//game[driver]/driver[@status='good']" >_temp\good.lst

rem //status from romstatus.xml
_bin\xidel -s output\romstatus.xml -e "//rom[Status='Runs slowly']/@name" >_temp\slowly.lst
_bin\xidel -s output\romstatus.xml -e "//rom[Status='Crashes']/@name" >_temp\crashes.lst
_bin\xidel -s output\romstatus.xml -e "//rom[Status='General nonworking']/@name" >_temp\nonworking.lst
_bin\xidel -s output\romstatus.xml -e "//rom[Status='Working']/@name" >_temp\working.lst

del _temp\bios-clones-parents.bat
for %%g in (bios.lst clones.lst parents.lst) do call :build_batch %%g bios-clones-parents

rem //list order matters, will be adding good clones if parent its not working
del _temp\crashes-slowly-nonworking.bat
for %%g in (crashes.lst slowly.lst nonworking.lst) do call :build_batch %%g crashes-slowly-nonworking 1

call :build_batch working.lst crashes-slowly-nonworking

if exist output\catver.ini (
	_bin\xidel -s --input-format=html output\catver.ini -e "extract( $raw, '^(\w+)=.*?Mature', 1, 'm*')" >_temp\mature.lst
	_bin\xidel -s --input-format=html output\catver.ini -e "extract( $raw, '^(\w+)=.*?Mahjong', 1, 'm*')" >_temp\mahjong.lst
	_bin\xidel -s --input-format=html output\catver.ini -e "extract( $raw, '^(\w+)=.*?Quiz', 1, 'm*')" >_temp\quiz.lst
	
	call :build_batch mature.lst MATURE 1
	
	for %%g in (mahjong.lst quiz.lst) do call :build_batch %%g mahjong-quiz 1
) 

md output\_batch 2>nul
for %%g in (_temp\*.bat) do (
	move /y %%g .\output\_batch\

)

set /a "_time=%time:~0,2%*3600+%time:~3,1%*600+%time:~4,1%*60+%time:~6,1%*10+%time:~7,1%"
set /a "_time=%_time%-%_time0%"
set /a "_hour=%_time%/(3600)"
set /a "_min=%_time%/60"
set /a "_sec=%_time%%%60"

cls&title ALL Done, Total Time: %_hour%:%_min%:%_sec%

cls
rem // compare the old datafile with the new datafile
if "%_datafile%"=="" pause&exit
if not exist _bin\mamediff.exe pause&exit

_bin\mamediff -d1 -s "%_datafile%" "output\%_file%"
move /y mamediff.log output\

rem //may be used to create and update rom set
del mamediff.dat

pause&exit
rem // ***************************** END OF SCRIPT ******************************************* 


:build_batch
rem //add all clones if the parent is in the list
if "%3"=="1" (
	for /f %%g in (_temp\%1) do (
		for /f %%h in ('findstr /e /c:"	%%g" _temp\cloneof.1') do (echo %%h) >>_temp\%1
	)
	sort /unique _temp\%1 /o _temp\%1
)

if not exist _temp\%2.bat (
	echo @echo off
	echo title "%_file%" ^^^| Build: %date%
	echo echo.=====================================================
	echo echo. This script will MOVE matched .zip files   
	echo echo.=====================================================
	echo choice /m "Continue?"
	echo if %%errorlevel%% equ 2 exit
	echo cls^&echo. Creating folders and moving files...
	
) >_temp\%2.bat

rem //order matters since there will be duplicates 
(echo md %~n1) >>_temp\%2.bat
_bin\xidel -s _temp\%1 -e "replace( $raw, '^(\w+)', '>nul 2>&1 move /y $1.zip .\\%~n1\\', 'm')" >>_temp\%2.bat


exit /b

:build_catver

rem //its a parent, look if any of the clones has a entry
if "%2"=="" (
	for /f %%g in ('findstr /e /c:"	%1" _temp\cloneof.1') do (
		>nul 2>&1 findstr /b "%%g=" _temp\catver.1 && (
			echo 	%%g
			for /f "tokens=2 delims==" %%h in ('findstr /b "%%g=" _temp\catver.1') do (echo %1=%%h) >>_temp\catver.ini
			exit /b
		)
	)
	(echo %1=Uncategorized) >>_temp\catver.ini
	exit /b
)

rem //its a clone, look if the parent have a entry
>nul 2>&1 findstr /b "%2=" _temp\catver.1 && (
	echo %2
	for /f "tokens=2 delims==" %%g in ('findstr /b "%2=" _temp\catver.1') do (echo %1=%%g) >>_temp\catver.ini
	exit /b
)


rem //nothing found, maybe it will find from another catver.ini
REM if exist sources\catver2.ini (
	REM for /f "delims=" %%g in ('findstr /rb /c:"%1=[A-Z].*" sources\catver2.ini') do (
		REM echo %%g
		REM (echo %%g) >>_temp\catver.ini
		REM exit /b
	REM )
REM )

echo %1 ---^> Uncategorized
(echo %1=Uncategorized) >>_temp\catver.ini

exit /b


:build_romstatus
rem //order matter since there may be double entires

>nul 2>&1 findstr /x "%1" _temp\crashes.lst && (
	echo %1 ---^> Crashes
	(echo 	^<Rom name="%1" version="1.0"^>
	echo 		^<Status^>Crashes^</Status^>
	echo 		^<StatusNumber^>3^</StatusNumber^>
	echo 	^</Rom^>) >>_temp\romstatus.xml
	exit /b
)
>nul 2>&1 findstr /x "%1" _temp\nonworking.lst && (
	echo %1 ---^> General nonWorking
	(echo 	^<Rom name="%1" version="1.0"^>
	echo 		^<Status^>General nonworking^</Status^>
	echo 		^<StatusNumber^>5^</StatusNumber^>
	echo 	^</Rom^>) >>_temp\romstatus.xml
	exit /b
)
>nul 2>&1 findstr /x "%1" _temp\slowly.lst && (
	echo %1 ---^> Runs Slowly
	(echo 	^<Rom name="%1" version="1.0"^>
	echo 		^<Status^>Runs slowly^</Status^>
	echo 		^<StatusNumber^>2^</StatusNumber^>
	echo 	^</Rom^>) >>_temp\romstatus.xml
	exit /b
)

(echo 	^<Rom name="%1" version="1.0"^>
echo 		^<Status^>Working^</Status^>
echo 		^<StatusNumber^>1^</StatusNumber^>
echo 	^</Rom^>) >>_temp\romstatus.xml

exit /b

:replace_array
_bin\xidel -s _temp\samples.xml -e "extract( $raw, '^\t?<%4 name=\""%2\""/?>(.+?)</game>', 1, 'ms')" >_temp\temp.1
_bin\xidel -s _temp\mame.c -e "replace( $raw, '<machine>%1</machine>', file:read-text('_temp\temp.1'))" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, 'machine=\""%1\""', 'sampleof=\""%3\""')" >_temp\mame.c

exit /b

:get_flags
rem //using MAME 0.160 status xml criteria found in "info.c"
rem //"GAME_SUPPORTS_SAVE" flag not supported in MAME 0.84

cls&title Converting and adding status flags....
_bin\xidel -s _temp\mame.xml -e "extract( $raw, '^<flags>(.+?)</flags>', 1, 'm*')" >_temp\temp.1
sort /unique _temp\temp.1 /o _temp/index.1

for /f "delims=" %%i in (_temp\index.1) do (
	echo %%i
	set _status=good
	set _emulation=good
	set _color=good
	set _sound=good
	set _graphic=good
	set "_cocktail="
	set "_protection="
	
	for /f %%g in ('_bin\xidel -s -e "matches( '%%i', 'NOT_WORKING|UNEMULATED_PROTECTION|NO_SOUND|WRONG_COLORS')"') do if %%g==true (set _status=preliminary)else (
		for /f %%h in ('_bin\xidel -s -e "matches( '%%i', 'IMPERFECT_COLORS|IMPERFECT_SOUND|IMPERFECT_GRAPHICS')"') do if %%h==true set _status=imperfect
	)
	for /f %%g in ('_bin\xidel -s -e "matches( '%%i', 'NOT_WORKING')"') do if %%g==true set _emulation=preliminary
	for /f %%g in ('_bin\xidel -s -e "matches( '%%i', 'WRONG_COLORS')"') do if %%g==true (set _color=preliminary)else (
		for /f %%h in ('_bin\xidel -s -e "matches( '%%i', 'IMPERFECT_COLORS')"') do if %%h==true set _color=imperfect
	)
	for /f %%g in ('_bin\xidel -s -e "matches( '%%i', 'NO_SOUND')"') do if %%g==true (set _sound=preliminary)else (
		for /f %%h in ('_bin\xidel -s -e "matches( '%%i', 'IMPERFECT_SOUND')"') do if %%h==true set _sound=imperfect
	)
	for /f %%g in ('_bin\xidel -s -e "matches( '%%i', 'IMPERFECT_GRAPHICS')"') do if %%g==true set _graphic=imperfect
	for /f %%g in ('_bin\xidel -s -e "matches( '%%i', 'NO_COCKTAIL')"') do if %%g==true set "_cocktail= cocktail=\"preliminary\""
	for /f %%g in ('_bin\xidel -s -e "matches( '%%i', 'UNEMULATED_PROTECTION')"') do if %%g==true set "_protection= protection=\"preliminary\""
	
	set "_flag=<driver status=\"!_status!\" emulation=\"!_emulation!\" color=\"!_color!\" sound=\"!_sound!\" graphic=\"!_graphic!\"!_cocktail!!_protection!/>"
	
	_bin\xidel -s _temp\mame.xml -e "replace( $raw, '<flags>%%i</flags>', '!_flag!', 'q')" >_temp\temp.1
	del _temp\mame.xml & ren _temp\temp.1 mame.xml
)

rem //all other games will have "good" status 
_bin\xidel -s _temp\mame.xml -e "replace( $raw, '<flags></flags>', '<driver status=\"good\" emulation=\"good\" color=\"good\" sound=\"good\" graphic=\"good\"/>', 'q')" >_temp\temp.1
del _temp\mame.xml & ren _temp\temp.1 mame.xml

exit /b


:add_size
cls&title Calculating and converting hex ROM sizes...
rem // transform every pair of rom continue size to a single tag
_bin\xidel -s _temp\mame.xml -e "replace( $raw, '^[\t ]*<cont size=\""([\w*+]+)\""/>\s+<cont size=\""([\w*+]+)\""/>', '<cont size=\""$1+$2\""/>', 'm')" >_temp\temp.1
del _temp\mame.xml & ren _temp\temp.1 mame.xml

for /f %%g in ('_bin\xidel -s _temp\mame.xml -e "matches( $raw, '<cont size=\""[\w*+]+\""/>\s+<cont size=\""[\w*+]+\""/>')"') do if %%g==true goto :add_size

rem //add rom continue to rom size
_bin\xidel -s _temp\mame.xml -e "replace( $raw, '<rom name=\""([\w\s&#=.-]+)\"" size=\""([\w*+]+)\"" crc=\""(\w*)\"" sha1=\""(\w*)\"" status=\""(nodump|baddump)\""/>\s+<cont size=\""([\w*+]+)\""/>', '<rom name=\""$1\"" size=\""$2+$6\"" crc=\""$3\"" sha1=\""$4\"" status=\""$5\""/>', 'm')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '<rom name=\""([\w\s&#=.-]+)\"" size=\""([\w*+]+)\"" crc=\""(\w*)\"" sha1=\""(\w*)\""/>\s+<cont size=\""([\w*+]+)\""/>', '<rom name=\""$1\"" size=\""$2+$5\"" crc=\""$3\"" sha1=\""$4\""/>', 'm')" >_temp\mame.xml

rem // convert hex to dec, multiplications, additions
_bin\xidel -s _temp\mame.xml -e "extract( $raw, 'size=\""([\w+*]+)\""', 1, '*')" >_temp\temp.1
sort /unique _temp\temp.1 /o _temp\index.1

del _temp\sol.equ 2>nul
for /f %%g in (_temp\index.1) do (
	set /a "_sol=%%g"
	(echo %%g	!_sol!) >>_temp\sol.equ
)

rem //replace solutions into mame.xml
for /f "tokens=1,2" %%g in (_temp\sol.equ) do (
	echo %%g ---^> %%h
	_bin\xidel -s _temp\mame.xml -e "replace( $raw, 'size=\""%%g\""', 'size=\""%%h\""', 'qi')" >_temp\temp.1
	del _temp\mame.xml & ren _temp\temp.1 mame.xml
)

exit /b


:build_mame

REM ****** line counter ************	
set /a _count_lines+=1
set /a "_percent=(%_count_lines%*100)/%_total_lines%"
title Building mame.c...%_count_lines% / %_total_lines% ^( %_percent% %% ^)

for /f %%g in ('_bin\xidel -s _temp\games.1 -e "extract( $raw, '^<game name=\""(\w+)\"".+', 1, 'm*')"') do (
	for /f %%h in ('_bin\xidel -s _temp\driver.c -e "matches( $raw, '^[\t ]*ROM_START\([\t ]*%%g[\t ]*\)', 'm')"') do if %%h==true (
		for /f %%i in ('_bin\xidel -s _temp\main.lst -e "matches( $raw, '^%%g$', 'm')"') do if %%i==true (
			for /f %%j in ('_bin\xidel -s _temp\mame.c -e "matches( $raw, '^<game name=\""%%g\""', 'm')"') do if %%j==false (
				(_bin\xidel -s _temp\games.1 -e "extract( $raw, '^<game name=\""%%g\"".+', 0, 'm')"
				_bin\xidel -s _temp\driver.c -e "extract( $raw, '^[\t ]*ROM_START\([\t ]*%%g[\t ]*\)\s+(.+?)ROM_END', 1, 'ms*')"
				echo ^</game^>)>>_temp\mame.c
				echo 	%%g
			)else (echo %%g[%1]	DUPLICATED) >>_temp\mame.log
		)else (echo %%g[%1]	game missing in Drivers.c) >>_temp\mame.log
	)else (echo %%g[%1]	ROM_START missing) >>_temp\mame.log
)
exit /b

:import_machine
rem //do import substitution, extracts multiple times
_bin\xidel -s _temp\machine.xml -e "//machine[import]/import/@name" >_temp\index.1
sort /unique _temp\index.1 /o _temp\index.1

for /f %%g in (_temp\index.1) do (
	_bin\xidel -s _temp\machine.xml -e "extract( $raw, '^<machine name=\""%%g\"">(.*?)</machine>', 1, 'sm')" >_temp\temp.1
	_bin\xidel -s _temp\machine.xml -e "replace( $raw, '^\t?<import name=\""%%g\""/>', file:read-text('_temp\temp.1'), 'm')" >_temp\temp.2
	del _temp\machine.xml & ren _temp\temp.2 machine.xml
)

for /f %%g in ('_bin\xidel -s _temp\machine.xml -e "matches( $raw, '<import name=\""\w+\""/>')"') do if %%g==true goto :import_machine

rem //clean empty lines
_bin\xidel -s _temp\machine.xml -e "replace( $raw, '^\r\n', '','m')" >_temp\temp.1
del _temp\machine.xml & ren _temp\temp.1 machine.xml
exit /b

:clean_file
if "%2"=="1" cls&title Cleanning %1...

rem //normalize carriage return
for /f %%g in ('_bin\xidel -s "_temp\%1" -e "matches( $raw, '\w\n')"') do if %%g==true (
	_bin\xidel -s "_temp\%1" -e "replace( $raw, '\r', '')" >_temp\temp.1
	_bin\xidel -s _temp\temp.1 -e "replace( $raw, '\n', codepoints-to-string((13,10)))" >"_temp\%1"
)

rem //remove comments lines in source files
_bin\xidel -s "_temp\%1" -e "replace( $raw, '://', '', 'q')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '/\*.*?\*/', '')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^[\t ]*/\*.+?\*/', '', 'ms')" >_temp\temp.1
_bin\xidel -s _temp\temp.1 -e "replace( $raw, '//.+', '')" >_temp\temp.2
_bin\xidel -s _temp\temp.2 -e "replace( $raw, '^[\t ]*#if 0.+?#endif', '', 'ms')" >"_temp\%1"

rem //remove false conditions for code execution
for /f %%g in ('_bin\xidel -s "_temp\%1" -e "matches( $raw, '^[\t ]*#define[\t ](\w+)[\t ]+0[\t ]*$', 'm')"') do if %%g==false exit /b

_bin\xidel -s "_temp\%1" -e "extract( $raw, '^[\t ]*#define[\t ](\w+)[\t ]+0[\t ]*$', 1, 'm*')" >_temp\index.1
sort /unique _temp\index.1 /o _temp\index.1

for /f %%g in (_temp\index.1) do (
	if "%2"=="1" echo %%g
	_bin\xidel -s "_temp\%1" -e "replace( $raw, '^[\t ]*#if[\t ]%%g.+?(?:#else|#endif)', '', 'ms')" >_temp\temp.1
	_bin\xidel -s _temp\temp.1 -e "replace( $raw, '^[\t ]*#if[\t ]\W%%g(.+?)(?:#else.+?)?#endif', '$1', 'ms')" >"_temp\%1"
)
exit /b

:find_samples
rem //alternative search for not found samples
set _name=%1
set _name=%_name:_sample_names=%

for /f %%g in ('_bin\xidel -s _temp\samples.equ -e "matches( $raw, '\t%_name%_\w+$', 'm')"') do if %%g==true (
	_bin\xidel -s _temp\samples.equ -e "replace( $raw, '\t%_name%_\w+$', '	%_name%_sample_names	%2', 'm')" >_temp\temp.1
	del _temp\samples.equ & ren _temp\temp.1 samples.equ
)

exit /b

:get_custom
rem //unplayable slow games for romstatus.xml

(echo namcos22.c
echo namcos11.c
echo namcos12.c
echo zn.c
echo stv.c
echo midxunit.c
echo midvunit.c
echo harddriv.c
echo vamphalf.c
echo atarigt.c
echo gaelco3d.c
echo rabbit.c
echo drivedge
echo mmaulers
echo gaiapols) >_temp\custom.lst


REM *crystal.c
REM namcos22.c
REM *namcos21.c
REM namcos11.c
REM namcos12.c
REM zn.c
REM stv.c
REM *groundfx.c
REM *midwunit.c
REM midxunit.c
REM midvunit.c
REM harddriv.c
REM *superchs.c
REM vamphalf.c
REM atarigt.c
REM *fuukifg3.c
REM gaelco3d.c
REM rabbit.c
REM **undrfire.c
REM **psikyosh.c
REM **itech32.c
REM **namconb1.c
REM **multi32.c
REM **ms32.c
REM **model1.c
REM **midtunit.c
REM **megasys1.c
REM **deco32.c
REM **segaxbd.c
REM **segaybd.c
REM **system32.c
REM **taito_f3.c
REM **atarig42.c
REM **atarigx2.c
REM **deco_mic.c
REM **konamigx.c
REM **namcos2.c
REM **pgm.c
REM *wcbowl
REM *sftm
REM *shufshot
REM drivedge
REM *daraku
REM *machbrkr
REM *cbombers
REM mmaulers
REM gaiapols
REM *outfxies
REM *commandw


exit /b



REM GAMEX(YEAR,NAME,PARENT,MACHINE,[INPUT,INIT,MONITOR],COMPANY,FULLNAME,FLAGS)
REM GAME(YEAR,NAME,PARENT,MACHINE,[INPUT,INIT,MONITOR],COMPANY,FULLNAME)

REM //GAMEB=BIOS, GAMEX=Flags
REM GAMEBX(YEAR,NAME,PARENT,BIOS,MACHINE,[INPUT,INIT,MONITOR],COMPANY,FULLNAME,FLAGS)
REM GAMEB(YEAR,NAME,PARENT,BIOS,MACHINE,[INPUT,INIT,MONITOR],COMPANY,FULLNAME)