package main

import "core:c"
import "core:fmt"
import "core:strings"
import "core:time"
import im "vendor/odin-imgui"

WORKSPACE_SIDEBAR_WIDTH: f32 = 260
WORKSPACE_STATUS_BAR_H :: f32(24)

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
	@(static) query_time_ms: f64
	@(static) pg_major_version: i32

	display := im.GetIO().DisplaySize

	Workspace_Sidebar(
		{
			state = state,
			display_h = display.y,
			loaded_dbs = &loaded_dbs,
			dbs_loaded = &dbs_loaded,
			selected_db = &selected_db,
			prev_selected_db = &prev_selected_db,
			loaded_schemas = &loaded_schemas,
			schemas_loaded = &schemas_loaded,
			selected_schema = &selected_schema,
			prev_selected_schema = &prev_selected_schema,
			loaded_tables = &loaded_tables,
			tables_loaded = &tables_loaded,
			selected_table = &selected_table,
			query_result = &query_result,
			prev_selected_table = &prev_selected_table,
			query_time_ms = &query_time_ms,
			pg_major_version = &pg_major_version,
		},
	)

	// ── Shared content area ───────────────────────────────────────────────────
	im.SetNextWindowPos({SIDEBAR_WIDTH, 0}, .Always)
	im.SetNextWindowSize({display.x - SIDEBAR_WIDTH, display.y - WORKSPACE_STATUS_BAR_H}, .Always)
	im.Begin(
		"##content",
		nil,
		{.NoMove, .NoResize, .NoCollapse, .NoTitleBar, .NoScrollbar, .NoScrollWithMouse},
	)
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
	right_x :=
		im.GetWindowWidth() - style.WindowPadding.x - row_w - refresh_w - style.ItemSpacing.x
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

	sb_props := StatusBar_Props {
		y_pos            = display.y - WORKSPACE_STATUS_BAR_H,
		display_w        = display.x,
		query_time_ms    = f32(query_time_ms),
		state            = state,
		pg_major_version = pg_major_version,
	}
	StatusBar(&sb_props)
}

Workspace_SidebarProps :: struct {
	state:                ^App_State,
	display_h:            f32,
	loaded_dbs:           ^[]string,
	dbs_loaded:           ^bool,
	selected_db:          ^string,
	prev_selected_db:     ^string,
	loaded_schemas:       ^[]string,
	schemas_loaded:       ^bool,
	selected_schema:      ^string,
	prev_selected_schema: ^string,
	loaded_tables:        ^[]string,
	tables_loaded:        ^bool,
	selected_table:       ^string,
	query_result:         ^QueryResult,
	prev_selected_table:  ^string,
	query_time_ms:        ^f64,
	pg_major_version:     ^i32,
}

Workspace_Sidebar :: proc(props: Workspace_SidebarProps) {
	switch conn in props.state.conn {
	case PQ_Conn:
		pg_conn := conn

		if !props.dbs_loaded^ || props.state.db_needs_reload {
			dbs, err := pg_get_dbs(pg_conn)
			if err != nil {panic(err.(DB_OpenFailed).message)}
			props.loaded_dbs^ = dbs
			props.dbs_loaded^ = true
			props.state.db_needs_reload = false
			props.pg_major_version^ = pg_server_version_major(pg_conn)
			props.state.encoding = pg_client_encoding(pg_conn)
			props.state.read_only = pg_is_read_only(pg_conn)
			current_db := pg_current_db(pg_conn)
			props.selected_db^ =
				current_db if current_db != "" else (props.loaded_dbs^[0] if len(props.loaded_dbs^) > 0 else "")
			props.prev_selected_db^ = props.selected_db^
			props.schemas_loaded^ = false
			props.selected_schema^ = ""
			props.prev_selected_schema^ = ""
			props.loaded_tables^ = {}
			props.tables_loaded^ = false
			props.selected_table^ = ""
			props.query_result^ = {}
			props.prev_selected_table^ = ""
		}

		if props.selected_db^ != props.prev_selected_db^ {
			new_conn, err := pg_connect_to_db(pg_conn, props.selected_db^)
			if err == nil {
				props.state.conn = new_conn
				pg_conn = new_conn
				props.schemas_loaded^ = false
			} else {
				props.loaded_schemas^ = {}
				props.schemas_loaded^ = true
			}
			props.selected_schema^ = ""
			props.prev_selected_schema^ = ""
			props.loaded_tables^ = {}
			props.tables_loaded^ = false
			props.selected_table^ = ""
			props.query_result^ = {}
			props.prev_selected_table^ = ""
			props.prev_selected_db^ = props.selected_db^
		}

		if !props.schemas_loaded^ {
			schemas, err := pg_get_schemas(pg_conn)
			if err == nil {
				props.loaded_schemas^ = schemas
				props.schemas_loaded^ = true
				props.selected_schema^ =
					props.loaded_schemas^[0] if len(props.loaded_schemas^) > 0 else ""
			}
		}

		if props.selected_schema^ != props.prev_selected_schema^ {
			props.loaded_tables^ = {}
			props.tables_loaded^ = false
			props.selected_table^ = ""
			props.query_result^ = {}
			props.prev_selected_table^ = ""
			if props.selected_schema^ != "" {
				tables, err := pg_get_tables(pg_conn, props.selected_schema^)
				if err == nil {
					props.loaded_tables^ = tables
					props.tables_loaded^ = true
				}
			}
			props.prev_selected_schema^ = props.selected_schema^
		}

		if props.selected_table^ != props.prev_selected_table^ {
			props.query_result^ = {}
			props.query_time_ms^ = 0
			if props.selected_table^ != "" && props.selected_schema^ != "" {
				q := fmt.tprintf(
					`SELECT * FROM "%s"."%s" LIMIT 1000`,
					props.selected_schema^,
					props.selected_table^,
				)
				t := time.tick_now()
				result, err := pg_run_query(pg_conn, q)
				props.query_time_ms^ = time.duration_milliseconds(time.tick_since(t))
				if err == nil {props.query_result^ = result}
			}
			props.prev_selected_table^ = props.selected_table^
		}

		im.SetNextWindowPos({0, 0}, .Always)
		im.SetNextWindowSize({SIDEBAR_WIDTH, props.display_h - WORKSPACE_STATUS_BAR_H}, .Always)

		im.PushStyleVar(.WindowBorderSize, 0)
		defer im.PopStyleVar()

		im.Begin("DBs", nil, {.NoMove, .NoResize, .NoCollapse, .NoScrollbar, .NoTitleBar})
		defer im.End()

		im.Text("Database")
		im.SetNextItemWidth(-1)
		db_label := strings.clone_to_cstring(
			props.selected_db^ if props.selected_db^ != "" else "Select database...",
		)
		defer delete(db_label)
		if im.BeginCombo("##db_select", db_label) {
			for db in props.loaded_dbs^ {
				cname := strings.clone_to_cstring(db)
				defer delete(cname)
				if im.Selectable(cname, props.selected_db^ == db) {
					props.selected_db^ = db
					props.loaded_schemas^ = nil
					props.schemas_loaded^ = false
					props.tables_loaded^ = false
					props.loaded_tables^ = nil
				}
			}
			im.EndCombo()
		}

		im.Spacing()
		im.Text("Schema")
		im.SetNextItemWidth(-1)
		schema_label := strings.clone_to_cstring(
			props.selected_schema^ if props.selected_schema^ != "" else "Select schema...",
		)
		defer delete(schema_label)
		if im.BeginCombo("##schema_select", schema_label) {
			for s in props.loaded_schemas^ {
				cname := strings.clone_to_cstring(s)
				defer delete(cname)
				if im.Selectable(cname, props.selected_schema^ == s) {
					props.selected_schema^ = s
				}
			}
			im.EndCombo()
		}

		im.Spacing()
		im.Text("Tables")
		im.BeginChild("##tables_list", {-1, -1}, {.Borders})
		for tbl in props.loaded_tables^ {
			cname := strings.clone_to_cstring(tbl)
			defer delete(cname)
			if im.Selectable(cname, props.selected_table^ == tbl) {
				props.selected_table^ = tbl
			}
		}
		im.EndChild()

	case SQLite_Conn:
		sq_conn := conn

		if !props.tables_loaded^ || props.state.db_needs_reload {
			props.state.db_needs_reload = false
			props.loaded_tables^ = sqlite_get_tables(sq_conn)
			props.tables_loaded^ = true
			props.selected_table^ = ""
			props.query_result^ = {}
			props.prev_selected_table^ = ""
		}

		if props.selected_table^ != props.prev_selected_table^ {
			props.query_result^ = {}
			props.query_time_ms^ = 0
			if props.selected_table^ != "" {
				q := fmt.tprintf(`SELECT * FROM "%s" LIMIT 1000`, props.selected_table^)
				t := time.tick_now()
				result, err := sqlite_run_query(sq_conn, q)
				props.query_time_ms^ = time.duration_milliseconds(time.tick_since(t))
				if err == nil {props.query_result^ = result}
			}
			props.prev_selected_table^ = props.selected_table^
		}

		im.SetNextWindowPos({0, 0}, .Always)
		im.SetNextWindowSize({SIDEBAR_WIDTH, props.display_h - WORKSPACE_STATUS_BAR_H}, .Always)
		im.Begin("Tables", nil, {.NoMove, .NoResize, .NoCollapse, .NoScrollbar, .NoTitleBar})
		defer im.End()

		im.Text("Tables")
		im.BeginChild("##tables_list", {-1, -1}, {.Borders})
		for tbl in props.loaded_tables^ {
			cname := strings.clone_to_cstring(tbl)
			defer delete(cname)
			if im.Selectable(cname, props.selected_table^ == tbl) {
				props.selected_table^ = tbl
			}
		}
		im.EndChild()
	}
}
