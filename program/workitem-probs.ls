#use "base.decls"

typedef TEXTFIELD_CHAR = (UPPERCASE | 

typedef NAME = LOWERCASE (LOWERCASE)* ;;
typedef UPPERCASENAME = UPPERCASE (UPPERCASE)*;;

typedef LASTCOMMAFIRST = UPPERCASENAME ", " UPPERCASENAME ;;
typedef FIRSTTHENLAST = NAME " " NAME;;

capitalize = [LASTCOMMAFIRST <=> FIRSTTHENLAST
{}]
