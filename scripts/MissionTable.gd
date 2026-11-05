class_name MissionTable
extends MissionGroup

## A Table (new 2026-11-05, branch feature/table): the wrapper ABOVE stages. A mission always has its main table (the root of the outline tree - everything
## that is not inside a MissionTable belongs to it) and any number of extra Tables, which are top-level groups (parent_id == "") holding stages and
## pieces. Exactly one Table is on the physical table at a time (MissionData.active_table_id); the Switch Table effect resets the table to another one
## ("a magic portal that brings you somewhere totally else"): the pieces of the old Table go back in the box and the new Table is set up from scratch,
## so the same physical components can be used again - which is why the component limits count per Table.
##
## A Table is a MissionGroup (same id / name / visible / parent_id, shown in the outline tree and the working-group dropdown, deleted the same way);
## only the class tells it apart. It must stay at the top level (a Table is never inside another group). Tables are drawn in separate places of the
## editor space - they must not overlap - and a Table's player start squares are the start squares that lie on its floor
## (MissionData.player_start_cells_of()).
