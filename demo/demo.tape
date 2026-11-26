# Records the README showcase. Run from the repository root: vhs demo/demo.tape
# Needs the lessons cached already (:LearnCpp sync) and the plugins demo/init.lua borrows from lazy.nvim.
Output demo/demo.gif

Require nvim

Set Shell bash
Set FontFamily "MesloLGS NF"
Set FontSize 15
Set Width 1280
Set Height 760
Set Padding 14
Set Theme "Catppuccin Mocha"
Set TypingSpeed 70ms
Set Framerate 20

Hide
Type "nvim -n -u demo/init.lua demo/demo.cpp" Enter
Sleep 2.5s
Type "/string_view speak" Enter
Type ":nohlsearch" Enter
Sleep 500ms
Show

# Lessons about the symbol under the cursor
Sleep 1.5s
Type ":LearnCpp lookup"
Sleep 400ms
Enter
Sleep 3s
Enter
Sleep 2.5s
Type "66Gzt"
Sleep 3s

# Run the code block under the cursor
Type "6j"
Sleep 600ms
Type "r"
Sleep 3.5s
Hide
Type ":only" Enter
Show

# Browse the table of contents, open a quiz and reveal a solution
Type ":LearnCpp"
Sleep 300ms
Enter
Sleep 1.5s
Type "chapter 25 quiz"
Sleep 1.5s
Enter
Sleep 2s
Type "83Gzz"
Sleep 2s
Enter
Sleep 3.5s
