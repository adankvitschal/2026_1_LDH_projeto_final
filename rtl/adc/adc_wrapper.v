// =============================================================================
// adc_wrapper.v
// Bloco 1 — ADC Wrapper para DE10-Lite (Intel MAX10)
//
// IP utilizado : "adc_new_ip" (gerado pelo Qsys/Platform Designer)
// Interface    : Avalon-ST Command/Response (streaming)
//
// Frequência de amostragem: 48 kHz  (50 MHz / 1042 ≈ 47.984 kHz, erro < 0.04%)
// Canal utilizado          : CH0
// Saída                    : adc_data [11:0] + adc_valid (pulso 1 ciclo)
// =============================================================================

module adc_wrapper (
    input  wire        clk,            // 50 MHz system clock
    input  wire        rst_n,          // reset assíncrono, ativo-baixo
    input  wire        adc_pll_clk,    // clock PLL dedicado do ADC (ex: 10 MHz)
    input  wire        adc_pll_locked, // sinal de lock da PLL
    output wire [11:0] adc_data,       // amostra ADC de 12 bits
    output wire        adc_valid       // pulso de 1 ciclo por amostra
);

// ---------------------------------------------------------------------------
// 1. Parâmetros de temporização
// ---------------------------------------------------------------------------
localparam integer CLK_FREQ_HZ    = 50_000_000;
localparam integer SAMPLE_FREQ_HZ =     48_000;
localparam integer CLK_DIV        = CLK_FREQ_HZ / SAMPLE_FREQ_HZ; // 1041

localparam [4:0] ADC_CH0 = 5'd0; // canal 0

// ---------------------------------------------------------------------------
// 2. Gerador de sample_tick  (1 pulso a cada CLK_DIV ciclos → 48 kHz)
// ---------------------------------------------------------------------------
reg [10:0] div_cnt;
reg        sample_tick;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        div_cnt     <= 11'd0;
        sample_tick <= 1'b0;
    end else begin
        if (div_cnt == CLK_DIV - 1) begin
            div_cnt     <= 11'd0;
            sample_tick <= 1'b1;
        end else begin
            div_cnt     <= div_cnt + 11'd1;
            sample_tick <= 1'b0;
        end
    end
end

// ---------------------------------------------------------------------------
// 3. Sinais Avalon-ST Command (saída → IP)
// ---------------------------------------------------------------------------
reg        cmd_valid;
wire       cmd_ready;

// channel: 5 bits, startofpacket e endofpacket sempre 1 em transações simples
wire [4:0] cmd_channel        = ADC_CH0;
wire       cmd_startofpacket  = 1'b1;
wire       cmd_endofpacket    = 1'b1;

// ---------------------------------------------------------------------------
// 4. Sinais Avalon-ST Response (entrada ← IP)
// ---------------------------------------------------------------------------
wire        resp_valid;
wire [4:0]  resp_channel;
wire [11:0] resp_data;
wire        resp_startofpacket;
wire        resp_endofpacket;

// ---------------------------------------------------------------------------
// 5. Máquina de envio de comandos
//    Envia um comando ao IP quando sample_tick pulsa e o IP está pronto.
//    Mantém cmd_valid até que cmd_ready seja confirmado (handshake Avalon-ST).
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cmd_valid <= 1'b0;
    end else begin
        if (sample_tick) begin
            cmd_valid <= 1'b1;          // solicita nova conversão
        end else if (cmd_ready) begin
            cmd_valid <= 1'b0;          // IP aceitou — desfaz valid
        end
    end
end

// ---------------------------------------------------------------------------
// 6. Instância do IP gerado pelo Qsys
// ---------------------------------------------------------------------------
adc_new_ip u0 (
    // Clocks e reset
    .clock_clk              (clk),
    .reset_sink_reset_n     (rst_n),
    .adc_pll_clock_clk      (adc_pll_clk),
    .adc_pll_locked_export  (adc_pll_locked),

    // Canal de comando (Avalon-ST sink — enviamos conversões)
    .command_valid          (cmd_valid),
    .command_channel        (cmd_channel),
    .command_startofpacket  (cmd_startofpacket),
    .command_endofpacket    (cmd_endofpacket),
    .command_ready          (cmd_ready),       // ← IP avisa que aceitou

    // Canal de resposta (Avalon-ST source — IP nos devolve o resultado)
    .response_valid         (resp_valid),
    .response_channel       (resp_channel),
    .response_data          (resp_data),
    .response_startofpacket (resp_startofpacket),
    .response_endofpacket   (resp_endofpacket)
);

// ---------------------------------------------------------------------------
// 7. Captura da resposta
//    Registra o dado quando o IP sinaliza response_valid E o canal é CH0.
// ---------------------------------------------------------------------------
reg [11:0] data_reg;
reg        valid_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_reg  <= 12'd0;
        valid_reg <= 1'b0;
    end else begin
        valid_reg <= 1'b0;  // pulso de 1 ciclo por padrão
        if (resp_valid && (resp_channel == ADC_CH0)) begin
            data_reg  <= resp_data;
            valid_reg <= 1'b1;
        end
    end
end

assign adc_data  = data_reg;
assign adc_valid = valid_reg;

endmodule