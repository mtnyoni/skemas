package main
import pq "vendor/odin-postgresql"
import sqlite "vendor/odin-sqlite3"

Screen :: enum {
	ConnectionScreen,
	DatabaseViewScreen,
}

Conn :: union {
	PQ_Conn,
	SQLite_Conn,
}

PQ_Conn :: ^pq.Conn
SQLite_Conn :: ^sqlite.Connection

App_State :: struct {
	app_db:          ^sqlite.Connection,
	screen:          Screen,
	conn:            Conn,
	needs_db_reload: bool,
}
