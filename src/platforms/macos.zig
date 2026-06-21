/// rsync MAXCHILDPROCS — see main.c. OS-specific logic lives here.
pub fn get_max_child_procs() u32 {
    return 7;
}
