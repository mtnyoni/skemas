package main

import "core:c"
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

ConnectionStatus :: enum {
	Connected,
	Disconnected,
	Connecting,
}

App_State :: struct {
	app_db:          ^sqlite.Connection,
	screen:          Screen,
	conn:            Conn,
	conn_status:     ConnectionStatus,
	latency:         f32, // ms (fractional)
	db_needs_reload: bool,
	encoding:        string,
	read_only:       bool,
	current_page:    int,
	total_pages:     int,
}

SQLITE_NULL :: c.int(5)
