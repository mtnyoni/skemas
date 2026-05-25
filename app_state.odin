package main
import sqlite "vendor/odin-sqlite3"

Screen :: enum {
	ConnectionScreen,
	DatabaseViewScreen,
}

App_State :: struct {
	db:     ^sqlite.Connection,
	screen: Screen,
}
