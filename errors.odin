package main

DB_Error :: union {
	DB_OpenFailed,
	DB_ExecFailed,
	DB_PrepareFailed,
	DB_StepFailed,
}

DB_OpenFailed :: struct {
	message: string,
}

DB_ExecFailed :: struct {
	message: string,
}

DB_PrepareFailed :: struct {
	message: string,
}

DB_StepFailed :: struct {
	message: string,
}
