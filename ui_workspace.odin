package main

import "core:c"
import "core:fmt"
import "core:strings"
import im "vendor/odin-imgui"

UIWorkspace :: proc(state: ^App_State) {
	// Postgres-only
	@(static) loaded_dbs: []string
	@(static) dbs_loaded: bool
	@(static) selected_db: string
	@(static) prev_selected_db: string
	@(static) loaded_schemas: []string
	@(static) schemas_loaded: bool
	@(static) selected_schema: string
	@(static) prev_selected_schema: string

	// Shared
	@(static) loaded_tables: []string
	@(static) tables_loaded: bool
	@(static) selected_table: string
	@(static) query_result: QueryResult
	@(static) prev_selected_table: string

	display := im.GetIO().DisplaySize
	sidebar_w: f32 = 260

	switch conn in state.conn {

	// ── PostgreSQL ────────────────────────────────────────────────────────────
	case PQ_Conn:
		pg_conn := conn

		if !dbs_loaded || state.db_needs_reload {
			dbs, err := pg_get_dbs(pg_conn)
			if err != nil { panic(err.(DB_OpenFailed).message) }
			loaded_dbs = dbs
			dbs_loaded = true
			state.db_needs_reload = false
			current_db := pg_current_db(pg_conn)
			selected_db = current_db if current_db != "" else (loaded_dbs[0] if len(loaded_dbs) > 0 else "")
			prev_selected_db = selected_db
			schemas_loaded = false
			selected_schema = ""
			prev_selected_schema = ""
			loaded_tables = {}
			tables_loaded = false
			selected_table = ""
			query_result = {}
			prev_selected_table = ""
		}

		if selected_db != prev_selected_db {
			new_conn, err := pg_connect_to_db(pg_conn, selected_db)
			if err == nil {
				state.conn = new_conn
				pg_conn = new_conn
				schemas_loaded = false
			} else {
				loaded_schemas = {}
				schemas_loaded = true
			}
			selected_schema = ""
			prev_selected_schema = ""
			loaded_tables = {}
			tables_loaded = false
			selected_table = ""
			query_result = {}
			prev_selected_table = ""
			prev_selected_db = selected_db
		}

		if !schemas_loaded {
			schemas, err := pg_get_schemas(pg_conn)
			if err == nil {
				loaded_schemas = schemas
				schemas_loaded = true
				selected_schema = loaded_schemas[0] if len(loaded_schemas) > 0 else ""
			}
		}

		if selected_schema != prev_selected_schema {
			loaded_tables = {}
			tables_loaded = false
			selected_table = ""
			query_result = {}
			prev_selected_table = ""
			if selected_schema != "" {
				tables, err := pg_get_tables(pg_conn, selected_schema)
				if err == nil {
					loaded_tables = tables
					tables_loaded = true
				}
			}
			prev_selected_schema = selected_schema
		}

		if selected_table != prev_selected_table {
			query_result = {}
			if selected_table != "" && selected_schema != "" {
				q := fmt.tprintf(`SELECT * FROM "%s"."%s" LIMIT 1000`, selected_schema, selected_table)
				result, err := pg_run_query(pg_conn, q)
				if err == nil { query_result = result }
			}
			prev_selected_table = selected_table
		}

		// Sidebar
		im.SetNextWindowPos({0, 0}, .Always)
		im.SetNextWindowSize({sidebar_w, display.y}, .Always)
		im.Begin("DBs", nil, {.NoMove, .NoResize, .NoCollapse, .NoScrollbar, .NoTitleBar})
		defer im.End()

		im.Text("Database")
		im.SetNextItemWidth(-1)
		db_label := strings.clone_to_cstring(selected_db if selected_db != "" else "Select database...")
		defer delete(db_label)
		if im.BeginCombo("##db_select", db_label) {
			for db in loaded_dbs {
				cname := strings.clone_to_cstring(db)
				defer delete(cname)
				if im.Selectable(cname, selected_db == db) {
					selected_db = db
					loaded_schemas = nil
					schemas_loaded = false
					tables_loaded = false
					loaded_tables = nil
				}
			}
			im.EndCombo()
		}

		im.Spacing()
		im.Text("Schema")
		im.SetNextItemWidth(-1)
		schema_label := strings.clone_to_cstring(selected_schema if selected_schema != "" else "Select schema...")
		defer delete(schema_label)
		if im.BeginCombo("##schema_select", schema_label) {
			for s in loaded_schemas {
				cname := strings.clone_to_cstring(s)
				defer delete(cname)
				if im.Selectable(cname, selected_schema == s) {
					selected_schema = s
				}
			}
			im.EndCombo()
		}

		im.Spacing()
		im.Text("Tables")
		im.BeginChild("##tables_list", {-1, -1}, {.Borders})
		for tbl in loaded_tables {
			cname := strings.clone_to_cstring(tbl)
			defer delete(cname)
			if im.Selectable(cname, selected_table == tbl) {
				selected_table = tbl
			}
		}
		im.EndChild()

	// ── SQLite ────────────────────────────────────────────────────────────────
	case SQLite_Conn:
		sq_conn := conn

		if !tables_loaded || state.db_needs_reload {
			state.db_needs_reload = false
			loaded_tables = sqlite_get_tables(sq_conn)
			tables_loaded = true
			selected_table = ""
			query_result = {}
			prev_selected_table = ""
		}

		if selected_table != prev_selected_table {
			query_result = {}
			if selected_table != "" {
				q := fmt.tprintf(`SELECT * FROM "%s" LIMIT 1000`, selected_table)
				result, err := sqlite_run_query(sq_conn, q)
				if err == nil { query_result = result }
			}
			prev_selected_table = selected_table
		}

		// Sidebar
		im.SetNextWindowPos({0, 0}, .Always)
		im.SetNextWindowSize({sidebar_w, display.y}, .Always)
		im.Begin("Tables", nil, {.NoMove, .NoResize, .NoCollapse, .NoScrollbar, .NoTitleBar})
		defer im.End()

		im.Text("Tables")
		im.BeginChild("##tables_list", {-1, -1}, {.Borders})
		for tbl in loaded_tables {
			cname := strings.clone_to_cstring(tbl)
			defer delete(cname)
			if im.Selectable(cname, selected_table == tbl) {
				selected_table = tbl
			}
		}
		im.EndChild()
	}

	// ── Shared content area ───────────────────────────────────────────────────
	im.SetNextWindowPos({sidebar_w, 0}, .Always)
	im.SetNextWindowSize({display.x - sidebar_w, display.y}, .Always)
	im.Begin("##content", nil, {.NoMove, .NoResize, .NoCollapse, .NoTitleBar, .NoScrollbar, .NoScrollWithMouse})
	defer im.End()

	// Breadcrumb + toolbar
	style := im.GetStyle()
	if selected_db != "" {
		db_c := strings.clone_to_cstring(selected_db)
		defer delete(db_c)
		im.Text(db_c)
	}
	if selected_schema != "" {
		im.SameLine()
		im.TextDisabled("/")
		im.SameLine()
		sch_c := strings.clone_to_cstring(selected_schema)
		defer delete(sch_c)
		im.Text(sch_c)
	}
	if selected_table != "" {
		if selected_db != "" || selected_schema != "" {
			im.SameLine()
			im.TextDisabled("/")
			im.SameLine()
		}
		tbl_c := strings.clone_to_cstring(selected_table)
		defer delete(tbl_c)
		im.Text(tbl_c)
	}
	im.SameLine()
	im.Button("Data")

	refresh_lbl: cstring = "↻"
	row_lbl: cstring = "+ Row"
	refresh_w := im.CalcTextSize(refresh_lbl).x + style.FramePadding.x * 2
	row_w := im.CalcTextSize(row_lbl).x + style.FramePadding.x * 2
	right_x := im.GetWindowWidth() - style.WindowPadding.x - row_w - refresh_w - style.ItemSpacing.x
	im.SameLine(right_x)
	if im.Button(refresh_lbl) {
		prev_selected_table = ""
	}
	im.SameLine()
	im.Button(row_lbl)

	im.Separator()

	if selected_table != "" && len(query_result.headers) > 0 {
		col_count := c.int(len(query_result.headers))
		table_flags :=
			im.TableFlags_Borders |
			im.TableFlags_RowBg |
			im.TableFlags_ScrollX |
			im.TableFlags_ScrollY |
			im.TableFlags_Resizable |
			im.TableFlags_Reorderable
		avail := im.GetContentRegionAvail()
		if im.BeginTable("##tabledata", col_count, table_flags, avail) {
			im.TableSetupScrollFreeze(0, 1)
			for header in query_result.headers {
				cheader := strings.clone_to_cstring(header)
				defer delete(cheader)
				im.TableSetupColumn(cheader)
			}
			im.TableHeadersRow()
			for row in query_result.rows {
				im.TableNextRow()
				for cell, col in row {
					im.TableSetColumnIndex(c.int(col))
					ccell := strings.clone_to_cstring(cell)
					defer delete(ccell)
					im.TextUnformatted(ccell)
				}
			}
			im.EndTable()
		}
	}
}
