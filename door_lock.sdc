# Board oscillator confirmed as 50 MHz.
create_clock -name i_clk -period 20.000 [get_ports {i_clk}]
# External button is asynchronous; reset_sync synchronizes deassertion.
set_false_path -from [get_ports {i_rst}]
