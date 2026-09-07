interface apb_if(input logic pclk, input logic presetn);
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [31:0] paddr;
  logic [31:0] pwdata;
  logic [31:0] prdata;
endinterface

module counter_dut (apb_if vif);
  logic [31:0] count;

  always_ff @(posedge vif.pclk or negedge vif.presetn) begin
    if (!vif.presetn) begin
      count <= 0;
    end else if (vif.psel && vif.penable && vif.pwrite && vif.paddr == 32'h0) begin
      count <= vif.pwdata; // Load counter via APB Write
    end else begin
      count <= count + 1;  // Normal counter increment
    end
  end

  // APB Read logic
  always_comb begin
    if (vif.psel && vif.penable && !vif.pwrite && vif.paddr == 32'h0)
      vif.prdata = count;
    else
      vif.prdata = 32'h0;
  end
endmodule
