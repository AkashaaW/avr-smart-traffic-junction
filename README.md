# Smart Traffic Junction

A four-way traffic light controller written in AVR assembly for the ATmega328P (Arduino Uno, 16 MHz). It sequences vehicle signals, handles pedestrian crossings, and switches to flashing yellow in low light.

## How it works

- **Normal operation** runs a 24-phase traffic sequence. A Timer1 compare-match interrupt provides a 1 ms time base.
- **Pedestrian crossing** uses a push button with 20 ms debounce. The controller stores the request and serves it at an eligible all-red phase. All vehicle signals stay red while the seven-segment display counts down from 5 to 0. The controller ignores new requests during the crossing and for 5 seconds afterward.
- **Night mode** reads an LDR through the ADC. When it detects darkness, all four yellow lights flash at 1 Hz. The controller returns to normal operation after 5 continuous seconds of bright conditions.

## Arduino Uno pin map

| Traffic direction | Red | Yellow | Green |
| --- | --- | --- | --- |
| North | D3 | D4 | D5 |
| South | D6 | D7 | D8 |
| East | D9 | D10 | D11 |
| West | D12 | D13 | A0 |

| Peripheral | Connection |
| --- | --- |
| Pedestrian push button | D2, active-low with internal pull-up |
| LDR voltage divider output | A1 (ADC1) |
| 74HC595 shift register | A2 data, A3 latch, A4 clock |
| Pedestrian red LED | A5 |
| Common-anode seven-segment display | 74HC595 Q0–Q6 for segments a–g |
| Pedestrian green LED | 74HC595 Q7 |

## Build

Save the assembly source as `traffic_junction.asm`. With AVRA installed and `m328pdef.inc` available on its include path, run the following command to generate the HEX file.

```sh
avra -o traffic_junction.hex traffic_junction.asm
```
