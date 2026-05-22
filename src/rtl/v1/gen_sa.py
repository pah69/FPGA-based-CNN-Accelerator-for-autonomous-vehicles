# ============================================================
# Generate an explicitly instantiated weight-stationary
# systolic array: no SystemVerilog generate-for loops.
#
# This generator targets the PE version with these ports:
#   act_i, act_valid_i, act_o, act_valid_o
#   psum_i, psum_valid_i, psum_o, psum_valid_o
#   weight_i, weight_load_i, weight_switch_i
#   weight_o, weight_valid_o
#   overflow_clr_i, overflow_o
# ============================================================

from pathlib import Path


def generate_systolic_array(n: int, out_dir: str = ".") -> Path:
    if n < 1:
        raise ValueError("n must be >= 1")

    module_name = f"ws_sa_{n}x{n}"
    filename = Path(out_dir) / f"{module_name}.sv"

    with open(filename, "w", encoding="utf-8") as f:
        # ====================================================
        # Header and module ports
        # ====================================================
        f.write("// ============================================================\n")
        f.write(f"// Auto-generated {n}x{n} Weight-Stationary Systolic Array\n")
        f.write("// Explicit PE instantiation. No SystemVerilog generate loops.\n")
        f.write("// ============================================================\n")
        f.write("`timescale 1ns / 1ps\n")
        f.write("`default_nettype none\n\n")

        f.write(f"module {module_name} #(\n")
        f.write(f"    parameter int SIZE             = {n},\n")
        f.write("    parameter int DATA_WIDTH       = 8,\n")
        f.write("    parameter int LOCAL_PSUM_WIDTH = (2 * DATA_WIDTH) + $clog2(SIZE)\n")
        f.write(") (\n")
        f.write("    input  logic clk,\n")
        f.write("    input  logic rst_n,\n\n")

        f.write("    // Weight input: one weight enters from the top of each column.\n")
        f.write("    input  logic signed [(DATA_WIDTH*SIZE)-1:0] wgt_flatten_i,\n")
        f.write("    input  logic [SIZE-1:0]                    wgt_load_i,\n")
        f.write("    input  logic                               weight_switch_i,\n\n")

        f.write("    // Activation input: one activation enters from the left of each row.\n")
        f.write("    input  logic signed [(DATA_WIDTH*SIZE)-1:0] act_flatten_i,\n")
        f.write("    input  logic [SIZE-1:0]                    act_valid_i,\n\n")

        f.write("    // Final partial sums from the bottom row.\n")
        f.write("    output logic signed [(LOCAL_PSUM_WIDTH*SIZE)-1:0] psum_flatten_o,\n")
        f.write("    output logic [SIZE-1:0]                          psum_valid_o,\n\n")

        f.write("    // High after the weight stream reaches the bottom PE of each column.\n")
        f.write("    output logic [SIZE-1:0] wgt_load_done_o,\n\n")

        f.write("    // Sticky overflow flags from every PE: bit index = row*SIZE + column.\n")
        f.write("    input  logic             overflow_clr_i,\n")
        f.write("    output logic [SIZE*SIZE-1:0] overflow_flatten_o\n")
        f.write(");\n\n")

        f.write("    // NOTE:\n")
        f.write("    //   SIZE is used for port widths, but this file contains exactly\n")
        f.write(f"    //   {n}x{n} PE instances. Do not override SIZE to another value.\n\n")

        # ====================================================
        # Input unpacking
        # ====================================================
        f.write("    // ========================================================\n")
        f.write("    // Input unpacking\n")
        f.write("    // ========================================================\n")

        for r in range(n):
            f.write(f"    logic signed [DATA_WIDTH-1:0] act_row{r}_i;\n")
            f.write(
                f"    assign act_row{r}_i = "
                f"act_flatten_i[({r}*DATA_WIDTH)+:DATA_WIDTH];\n"
            )

        f.write("\n")

        for c in range(n):
            f.write(f"    logic signed [DATA_WIDTH-1:0] wgt_col{c}_i;\n")
            f.write(
                f"    assign wgt_col{c}_i = "
                f"wgt_flatten_i[({c}*DATA_WIDTH)+:DATA_WIDTH];\n"
            )

        f.write("\n")

        # ====================================================
        # Internal wires
        # ====================================================
        f.write("    // ========================================================\n")
        f.write("    // Internal routing wires\n")
        f.write("    // ========================================================\n")

        for r in range(n):
            for c in range(n):
                # Activation moves left to right.
                if c < n - 1:
                    f.write(
                        f"    logic signed [DATA_WIDTH-1:0] "
                        f"act_{r}_{c}_to_{r}_{c+1};\n"
                    )
                    f.write(
                        f"    logic                         "
                        f"act_v_{r}_{c}_to_{r}_{c+1};\n"
                    )

                # Weight moves top to bottom.
                if r < n - 1:
                    f.write(
                        f"    logic signed [DATA_WIDTH-1:0] "
                        f"wgt_{r}_{c}_to_{r+1}_{c};\n"
                    )
                    f.write(
                        f"    logic                         "
                        f"wgt_v_{r}_{c}_to_{r+1}_{c};\n"
                    )
                else:
                    f.write(f"    logic                         wgt_v_{r}_{c}_done;\n")

                # Partial sum moves top to bottom.
                if r < n - 1:
                    f.write(
                        f"    logic signed [LOCAL_PSUM_WIDTH-1:0] "
                        f"psum_{r}_{c}_to_{r+1}_{c};\n"
                    )
                    f.write(
                        f"    logic                               "
                        f"psum_v_{r}_{c}_to_{r+1}_{c};\n"
                    )
                else:
                    f.write(
                        f"    logic signed [LOCAL_PSUM_WIDTH-1:0] "
                        f"psum_{r}_{c}_out;\n"
                    )
                    f.write(
                        f"    logic                               "
                        f"psum_v_{r}_{c}_out;\n"
                    )

        f.write("\n")

        # ====================================================
        # Output packing
        # ====================================================
        f.write("    // ========================================================\n")
        f.write("    // Output packing\n")
        f.write("    // ========================================================\n")

        for c in range(n):
            f.write(
                f"    assign psum_flatten_o[({c}*LOCAL_PSUM_WIDTH)+:LOCAL_PSUM_WIDTH] "
                f"= psum_{n-1}_{c}_out;\n"
            )
            f.write(f"    assign psum_valid_o[{c}] = psum_v_{n-1}_{c}_out;\n")
            f.write(f"    assign wgt_load_done_o[{c}] = wgt_v_{n-1}_{c}_done;\n")

        f.write("\n")

        # ====================================================
        # PE instances
        # ====================================================
        f.write("    // ========================================================\n")
        f.write("    // PE array instantiation\n")
        f.write("    // ========================================================\n")

        for r in range(n):
            f.write(f"\n    // ---------------- ROW {r} ----------------\n")

            for c in range(n):
                # Inputs from array boundaries or neighboring PEs.
                act_i = f"act_row{r}_i" if c == 0 else f"act_{r}_{c-1}_to_{r}_{c}"
                act_valid_i = (
                    f"act_valid_i[{r}]"
                    if c == 0
                    else f"act_v_{r}_{c-1}_to_{r}_{c}"
                )

                psum_i = (
                    "{LOCAL_PSUM_WIDTH{1'b0}}"
                    if r == 0
                    else f"psum_{r-1}_{c}_to_{r}_{c}"
                )

                psum_valid_i = (
                    act_valid_i
                    if r == 0
                    else f"psum_v_{r-1}_{c}_to_{r}_{c}"
                )

                wgt_i = f"wgt_col{c}_i" if r == 0 else f"wgt_{r-1}_{c}_to_{r}_{c}"

                # Important:
                # Weight valid must propagate down the column.
                # Do not connect the same global load signal to every row.
                wgt_load_i_sig = (
                    f"wgt_load_i[{c}]"
                    if r == 0
                    else f"wgt_v_{r-1}_{c}_to_{r}_{c}"
                )

                # Outputs to array boundaries or neighboring PEs.
                act_o = "" if c == n - 1 else f"act_{r}_{c}_to_{r}_{c+1}"
                act_valid_o = "" if c == n - 1 else f"act_v_{r}_{c}_to_{r}_{c+1}"

                psum_o = (
                    f"psum_{r}_{c}_out"
                    if r == n - 1
                    else f"psum_{r}_{c}_to_{r+1}_{c}"
                )

                psum_valid_o = (
                    f"psum_v_{r}_{c}_out"
                    if r == n - 1
                    else f"psum_v_{r}_{c}_to_{r+1}_{c}"
                )

                wgt_o = "" if r == n - 1 else f"wgt_{r}_{c}_to_{r+1}_{c}"

                wgt_valid_o = (
                    f"wgt_v_{r}_{c}_done"
                    if r == n - 1
                    else f"wgt_v_{r}_{c}_to_{r+1}_{c}"
                )

                overflow_bit = f"overflow_flatten_o[({r}*SIZE)+{c}]"

                f.write("    pe #(\n")
                f.write("        .DATA_WIDTH(DATA_WIDTH),\n")
                f.write("        .LOCAL_PSUM_WIDTH(LOCAL_PSUM_WIDTH)\n")
                f.write(f"    ) pe_{r}_{c} (\n")
                f.write("        .clk            (clk),\n")
                f.write("        .rst_n          (rst_n),\n\n")

                f.write(f"        .act_i          ({act_i}),\n")
                f.write(f"        .act_valid_i    ({act_valid_i}),\n")
                f.write(f"        .act_o          ({act_o}),\n")
                f.write(f"        .act_valid_o    ({act_valid_o}),\n\n")

                f.write(f"        .psum_i         ({psum_i}),\n")
                f.write(f"        .psum_valid_i   ({psum_valid_i}),\n")
                f.write(f"        .psum_o         ({psum_o}),\n")
                f.write(f"        .psum_valid_o   ({psum_valid_o}),\n\n")

                f.write(f"        .weight_i       ({wgt_i}),\n")
                f.write(f"        .weight_load_i  ({wgt_load_i_sig}),\n")
                f.write("        .weight_switch_i(weight_switch_i),\n")
                f.write(f"        .weight_o       ({wgt_o}),\n")
                f.write(f"        .weight_valid_o ({wgt_valid_o}),\n\n")

                f.write("        .overflow_clr_i (overflow_clr_i),\n")
                f.write(f"        .overflow_o     ({overflow_bit})\n")
                f.write("    );\n\n")

        f.write(f"endmodule : {module_name}\n\n")
        f.write("`default_nettype wire\n")

    print(f">>> Success: generated {filename} with {n*n} explicit PE instances")
    return filename


if __name__ == "__main__":
    TARGET_N = 3
    generate_systolic_array(TARGET_N)