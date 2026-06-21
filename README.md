```
@@@@@@@  @@@@@@@@ @@@@@@@@ @@@      @@@@@@@@  @@@@@@@ @@@@@@@ 
@@!  @@@ @@!      @@!      @@!      @@!      !@@        @!!   
@!@!!@!  @!!!:!   @!!!:!   @!!      @!!!:!   !@!        @!!   
!!: :!!  !!:      !!:      !!:      !!:      :!!        !!:   
:   : : : :: ::   :       : ::.: : : :: ::   :: :: :    :    
```
---

To mirror is to `reflect` 🪞. `reflect` is the spiritual successor to `rsync`, the venerable tool, 
I am doing this to better understand Zig and to allow the legendary tool to live on.

## Goals
1. To 100% command line flag compatible with rsync v3.4.4 (at the time of writing this)
1. To bring rsync into a newer language Zig which allows that low level control but greatly enhances ergonomics! [testing, cross compile, optimizations]
1. To create `libreflect` which in essence is librsync. This will allow developers much more granularity in enhancement. (This is why I need it)
1. So I can gain a deeper understanding of the famous "delta" algorithm. 