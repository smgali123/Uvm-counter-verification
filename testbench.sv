`include "uvm_macros.svh"
import uvm_pkg::*;

class apb_item extends uvm_sequence_item;
  rand bit        pwrite;
  rand bit [31:0] paddr;
  rand bit [31:0] pwdata;
       bit [31:0] prdata;

  `uvm_object_utils_begin(apb_item)
    `uvm_field_int(pwrite, UVM_ALL_ON)
    `uvm_field_int(paddr,  UVM_ALL_ON)
    `uvm_field_int(pwdata, UVM_ALL_ON)
    `uvm_field_int(prdata, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "apb_item");
    super.new(name);
  endfunction
endclass

class apb_sequence extends uvm_sequence #(apb_item);
  `uvm_object_utils(apb_sequence)

  function new(string name = "apb_sequence");
    super.new(name);
  endfunction

  task body();
    // 1. Write to load the counter
    req = apb_item::type_id::create("req");
    start_item(req);
    req.randomize() with { pwrite == 1; paddr == 32'h0; pwdata == 32'hA5; };
    finish_item(req);

    // 2. Read back the counter value
    req = apb_item::type_id::create("req");
    start_item(req);
    req.randomize() with { pwrite == 0; paddr == 32'h0; };
    finish_item(req);
  endtask
endclass

class apb_driver extends uvm_driver #(apb_item);
  `uvm_component_utils(apb_driver)
  virtual apb_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Could not get vif")
  endfunction

  task run_phase(uvm_phase phase);
    vif.psel <= 0;
    vif.penable <= 0;
    
    forever begin
      seq_item_port.get_next_item(req);
      
      // APB Setup Phase
      @(posedge vif.pclk);
      vif.psel   <= 1;
      vif.penable<= 0;
      vif.pwrite <= req.pwrite;
      vif.paddr  <= req.paddr;
      if (req.pwrite) vif.pwdata <= req.pwdata;

      // APB Access Phase
      @(posedge vif.pclk);
      vif.penable <= 1;

      // Wait for complete
      @(posedge vif.pclk);
      if (!req.pwrite) req.prdata = vif.prdata;
      
      vif.psel    <= 0;
      vif.penable <= 0;
      
      seq_item_port.item_done();
    end
  endtask
endclass

class apb_monitor extends uvm_monitor;
  `uvm_component_utils(apb_monitor)
  virtual apb_if vif;
  uvm_analysis_port #(apb_item) ap_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap_port = new("ap_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "Could not get vif")
  endfunction

  task run_phase(uvm_phase phase);
    apb_item trans;
    forever begin
      @(posedge vif.pclk);
      if (vif.psel && vif.penable) begin
        trans = apb_item::type_id::create("trans");
        trans.pwrite = vif.pwrite;
        trans.paddr  = vif.paddr;
        if (vif.pwrite) trans.pwdata = vif.pwdata;
        else            trans.prdata = vif.prdata;
        ap_port.write(trans);
        `uvm_info("MON", trans.sprint(), UVM_LOW)
      end
    end
  endtask
endclass

class apb_agent extends uvm_agent;
  `uvm_component_utils(apb_agent)
  
  uvm_sequencer #(apb_item) sqr;
  apb_driver                drv;
  apb_monitor               mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sqr = uvm_sequencer#(apb_item)::type_id::create("sqr", this);
    drv = apb_driver::type_id::create("drv", this);
    mon = apb_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass

class apb_env extends uvm_env;
  `uvm_component_utils(apb_env)
  apb_agent agent;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = apb_agent::type_id::create("agent", this);
  endfunction
endclass

class apb_test extends uvm_test;
  `uvm_component_utils(apb_test)
  apb_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = apb_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    apb_sequence seq = apb_sequence::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.agent.sqr);
    #50; 
    phase.drop_objection(this);
  endtask
endclass

module tb_top;
  logic pclk;
  logic presetn;

  apb_if     vif(pclk, presetn);
  counter_dut dut(vif);

  // Waveform generation setup
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
  end

  initial begin
    pclk = 0;
    forever #5 pclk = ~pclk;
  end

  initial begin
    presetn = 0;
    #15 presetn = 1;
  end

  initial begin
    uvm_config_db#(virtual apb_if)::set(null, "*", "vif", vif);
    run_test("apb_test");
  end
endmodule
