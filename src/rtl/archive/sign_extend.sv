module sign_extend #(
    parameter DATA_WIDTH = 16
) (
    unextend,
    extended
);

  input  [DATA_WIDTH-1  :0] unextend;
  output [DATA_WIDTH*2-1:0] extended;

  assign extended = {
    {16{unextend[15]}}, unextend
  };  // 16 * 16th bit of "unenxtend" + 15bit "unextend"


endmodule
