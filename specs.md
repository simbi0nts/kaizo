THIS FILE FOR MANUAL CHANGE ONLY

Concept stage.

Project Kaizo
General Purpose LLM Language (GPLM)

Goal: build programming language for LLM to use, so human stay out of manual programming and code review. 
All manual effort goes to create concept, check funcionality and ui/ux design.
GPLM goal is to combine best features from all available programming languages, but only functional ones.
Features for readability and other made "to make developer life easy" could be ignored. 

Main pinpoints:

Development:
* It is a long lasting project, development should be made in multiple granualar steps. 
  Each step should be both documented in separate file (in folder .dev) and version control (git)
* Steps should be described such that the whole process could be continued from another machine.
* There would be several test projects, correct completion with GPLM would be meaning success of the GPLM concept.

Theory 1:
Three parts functionality:
1) Single binary core file, that include all main instructions.
2) Libraries (separate folder). Could be shared with other users and agents. All optional functionalities, but ones that could be repurposed in other projects.
3) App. Binary or executable. Result of user request.

Test projects to check concept (put each in separate folder):
1) Snake game
2) Test page in browser (Hello world)
