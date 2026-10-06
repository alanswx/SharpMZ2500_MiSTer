# Core-specific timing constraints (the template's SharpMZ2500.sdc stays unmodified).
#
# jt12 (YM2203) phase generator: every register in it is gated by jt12's internal clock enable, which pulses at
# most once per 2 MHz cen (every ~43 clk_sys cycles), so paths inside it have at least two clk_sys cycles.
set_multicycle_path -from [get_registers {*|jt03:opn|*|jt12_pg:u_pg|*}] -to [get_registers {*|jt03:opn|*|jt12_pg:u_pg|*}] -setup -end 2
set_multicycle_path -from [get_registers {*|jt03:opn|*|jt12_pg:u_pg|*}] -to [get_registers {*|jt03:opn|*|jt12_pg:u_pg|*}] -hold -end 1
