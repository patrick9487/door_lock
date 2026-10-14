# Door Lock — EP1C3 / 50 MHz / LCD1602A

固定密碼預設 `123456`。輸入至少六位才可提交；不支援四位密碼。

## 2026-10-14 LCD 修正

- 板上 reset 按鍵放開為 3.3 V、按下為 0 V，因此頂層 `i_rst` 預設**低有效**。舊版高有效判斷會在放開時讓所有模組一直重置，LCD 無法初始化。`RESET_ACTIVE_LOW=0` 可供高有效來源使用，子模組仍使用內部高有效 reset。
- `.qsf` 已指定 `o_lcd_rw` 為 PIN_97，舊版卻未宣告該輸出。現已補上並固定為 0（寫入）。若 RW 實際接 FPGA，此修正才會控制它；請核對接線。
- 配置完成後自動產生 32 個時鐘週期的重置，再由 LCD 驅動等待 50 ms 後送初始化。初值使用 Quartus 的 FPGA register power-up 支援；外部 reset 非同步置位、同步解除。
- 一般 LCD 指令/資料等待 100 us，清屏/回原點及初始化維持較長等待。輸入、隱藏及顯示時間到期會排程更新，不再等待整個 100 ms 刷新空檔；先完成在途 byte，再重繪。遮蔽不是零延遲，補充 1 MHz 模擬的單字案例約 2 ms，測試上限為 10 ms。
- 鍵盤每行至少停留 3 個時鐘週期，避免低頻模擬時兩級同步造成錯行；50 MHz 下的原掃描速度不變。
- 新增 50 MHz 時鐘 SDC。它不是所有外部介面的完整時序約束，仍須在 Quartus 檢查綜合、Fitter 和 TimeQuest 報告。

## LCD 接線與上機確認

下表來自現有 QSF；尚未以實物電路圖確認。

| LCD 訊號 | FPGA 腳位 | 程式埠 |
|---|---|---|
| RS | PIN_96 | o_lcd_rs |
| RW | PIN_97 | o_lcd_rw，固定低 |
| E | PIN_98 | o_lcd_e |
| D4 | PIN_110 | o_lcd_data[0] |
| D5 | PIN_111 | o_lcd_data[1] |
| D6 | PIN_112 | o_lcd_data[2] |
| D7 | PIN_113 | o_lcd_data[3] |

四位模式使用 LCD 的 **D4–D7**，不是 D0–D3。reset 為 PIN_67，50 MHz 時鐘為 PIN_92。確認電源、共地及對比電壓；若 LCD 是較晚才上電，待供電穩定後按一次 reset。

重新完整編譯 `door_lock.qpf` 並下載新產生的 `.sof`。放開 reset 後第一排應出現 `ENTER PIN`；第二排在沒有輸入時本來就是空白，按數字後才出現星號。若仍為方塊，量測 PIN_67 放開為高、RW 持續為低，以及 E 是否在重置解除後開始產生脈衝，並核對 D4–D7 接線。

初始化沿用 `3,3,3,2` 四次半位元組，後續送 `28,08,01,06,0C`。寫入模式與等待時間依據 [Hitachi HD44780U datasheet](https://cdn-shop.adafruit.com/datasheets/HD44780.pdf)。1602A 相容模組的實際電氣規格仍應以其製造商資料為準。

## 測試

需安裝 Icarus Verilog (`iverilog`、`vvp`)：

```sh
sh testbench/run_tests.sh
# 加跑實際 50 MHz 參數的上電與 LCD 總線測試：
sh testbench/run_tests.sh --50mhz
```

包含原 PIN 輸入/比對/鍵盤測試、1/2 kHz 低頻鍵盤回歸、五位密碼拒絕、正確開鎖、第三次錯誤鎖定與恢復、無手動 reset 啟動、兩種 reset 極性、LCD 實體總線解碼與脈寬、第二排星號、明文遮蔽，以及清屏/回原點等待時間。

本次驗證為 RTL 模擬，未在這台電腦執行 Quartus 綜合或實物測試。

## 目前範圍

A 鍵修改密碼及 EEPROM 持久狀態尚未實作。reset 會清除錯誤次數及鎖定計時。`o_unlock_pulse` 是單拍事件，`o_locked` 表示錯誤次數觸發的暫時鎖定，並非直接控制鎖舌的保持輸出；蜂鳴器仍沿用原版固定高電位靜音設定。
