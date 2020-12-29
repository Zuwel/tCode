# **tCode - Turtle Instruction Language**
### *made by Zuwel*

---

## TODO
- &check; - Actually functioning?
- &check; - Flow control (label, goto, if)
- &cross; - Rednet communication / control
- &cross; - Auto resume / run state saving

---

## tCode (turtle-code) format:
- ### Header
    - format (string) - the file format, which must read "tCode" for to ensure interpreter compatibility
    - version (string) - the tCode version number, used for ensuring interpreter compatibility

- ### Commands
    - move (forward/up/down/back) <number> - moves the turtle either forward, up, down, back, with an optional command repeat parameter
    - turn (left/right) <number> - turns the turtle either left or right, with an optional command repeat parameter
    - place (forward/up/down) <text> - places a named block in the specified direction if possible
    - dig (false/true) - enables (true) or disables (false) the turtles ability to dig
    - suck (false/true) - enables (false) or disables (false) the turtles ability to suck
    - tooldir (front/up/down) - specifies the relative direction in which the turtle digs and sucks, forward, up, down
    - dump <text> - dumps all items, excluding valid fuel sources, or optionally, all of a specified item in the turtles inventory
    - home - turtle attempts to navigate home, either by tracing back its path ()
    - pos (x), (y), (z) - automatically tracks back to the specified position using the fastest route, using gps coordinates if possible or relative position.
    - look (north/south/east/west) - turns the turtle to face the specified rotation, using gps heading if possible or relative rotation.
    - label <text> - a label which references a line position within the tCode file
    - goto <text, number> - skips the execution back to a specified label within the tCode file
    - if (value) (=/>/</>=/<=) (value) (command) (args) checks if the comparison is true; if so, it will run the command specified. [if commands can be chained]
    - ifnot (value) (=/>/</>=/<=) (value) (command) (args) checks if the comparison is not true; if so, it will run the command specified. [ifnt commands can be chained]
    - var (set/unset/add/sub/mult/div) (name) (value) sets user variable which can be referenced in tcode with "#<name>"
    - usegps (bool) - if the turtle should use gps
    - lowfuelreturn (bool) - if the turtle should automatically return home if it only has the fuel required (plus margin) to return home
    - returnmethod (integer) - the method in which the turtle returns home, either by traceback (0), direct path (1), or rise and return (2)
    - fuelmargin (integer) - amount of additional fuel saved in addition to the minimum required to return home
    - digfilter (array) - array of blocks to consider digging (+) or not (-) ("(+/-) stone") [Warning: Could result in an automatic failure]
    -   If any inclusion (+) filters are specified, it is assumed that the turtle will only dig the specified blocks [Warning: Use digfilter inclusions with caution]
    - suckfilter (array) - array of blocks/items to consider sucking (+) or not (-) ("(+/-) diamond")
    -   If any inclusion (+) filters are specified, it is assumed that the turtle will only suck the specified blocks/items
    - _ - a simple marker indicating that the header section has been read to completion
- ### Rednet Commands
    - TODO

### Launch Arguments: (* is required)
- *filePath (string) - tcode text file path to read from
- hostName (string) - host name of the wirelessly controlling computer

### Usage:
> ##tcode filePath <filePath>