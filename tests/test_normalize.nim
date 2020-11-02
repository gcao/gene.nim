import ./helpers

test_normalize "(1 + 2)", "(+ 1 2)"

test_normalize "(.@test)", "(@ \"test\")"
test_normalize "(self .@test)", "(@ ^self self \"test\")"
test_normalize "(@test = 1)", "(@= \"test\" 1)"
