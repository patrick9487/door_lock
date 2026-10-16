# Door Lock — ATmega328P

這是獨立的 ATmega328P 移植版本，原資料夾內的 FPGA／Verilog 專案維持原樣。
預設硬體為 **Arduino Uno 相容板、ATmega328P、16 MHz、5V**。
若使用 Nano、8 MHz 或裸晶片，需依實際硬體調整 `platformio.ini`；這次不處理燒錄器、bootloader 或 fuse。

## 在 VS Code 開啟

1. 開啟這個 `ATmega328P` 資料夾（不是上一層 Quartus 專案）。
2. 安裝 PlatformIO IDE 擴充套件。
3. 執行 PlatformIO 的 **Build**，或終端輸入 `pio run -e uno`。
4. 本次只建立並編譯專案，沒有連線下載或燒錄晶片。

## 功能

- 預設密碼 `123456`；最多 4 組，每組 6～128 位，可包含前導零。
- A 進入管理；第一行 `Change/Add (1/1)`。
- 第二行每三秒切換 `<4 Password 1 6>`、`<4Press Enter 6>`。
- 4／6 切換組別；最後一組再按 6 直接新增；四組已滿不覆寫任何組別。
- # 進入修改；修改／新增頁第一行每三秒輪播標題、`Enter to Save`、`Delete to Back`。
- 數字輸入、* 退格、# 儲存／確認、D 取消／返回；D 不會刪除已存的密碼。
- 第二行以星號遮蔽；B 切換「最新一位顯示約 800 ms」模式。
- C 電鈴：響 200 ms、停 150 ms、響 200 ms；鎖定期間也能使用。
- 比對畫面約 100 ms；成功／失敗畫面約 2 秒；連續三次錯誤鎖定 30 秒。
- 不足六位不計入錯誤次數；比對所有組別皆失敗才計一次錯誤。
- RAM 暫存：重置或斷電後只剩預設一組 `123456`，不寫 EEPROM，也不修改電腦原始碼。
- 依原先流程，A 可直接進管理；尚未加入管理員舊密碼驗證或刪除整組功能。

## 檔案

- `include/DoorLockApp.h`：密碼庫、狀態流程、畫面內容及電鈴計時。
- `include/MatrixKeypad.h`：非阻塞逐行掃描、去抖動、單鍵及放開判斷。
- `include/Config.h`：接腳及蜂鳴器有效極性。
- `src/main.cpp`：Arduino 硬體介面，LCD 分次更新，不使用長時間 delay。
- `WIRING.md`：接線表。
- `test/host_tests.cpp`：可在電腦執行的控制器／掃描器回歸測試。

## 按鍵時間

每排約 1 ms，五輪確認按下約 20 ms、兩輪確認放開約 8 ms。
同時按多鍵會忽略，必須完全放開後再按；按住不連續重複輸入。
LCD 初始化只在 setup 執行，運作期間每次只更新一個有變化的字元。

## 參考

- [PlatformIO Uno 設定](https://docs.platformio.org/en/latest/boards/atmelavr/uno.html)
- [Arduino LiquidCrystal](https://github.com/arduino-libraries/LiquidCrystal)
