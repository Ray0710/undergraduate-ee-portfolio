# MSP430 single-digit calculator

**Undergraduate embedded systems lab · MSP430FR2355 · Energia · C/C++**

I built a calculator with a rotary potentiometer, step and reset buttons, and a seven-segment display. The potentiometer feeds the ADC and selects values from discrete bins. The step button advances the input sequence and the reset button returns to the initial prompt.

## Design

The original sketch prompts for operand A, the operation, and operand B, then calculates and displays the result. Both operands range from 1 to 9. The four operations are addition, subtraction, multiplication, and division. The display shows successive digits for results that need more than one character.

| Interface | Energia pin |
| --- | --- |
| Potentiometer ADC | 6 |
| Serial display data, latch, and clock | 11, 12, 13 |
| Step and reset buttons | 28, 30 |

The display driver serializes segment patterns with `shiftOut`. The two buttons use falling-edge interrupts.

## Archived firmware

[SingleDigitCalculator.ino](SingleDigitCalculator/SingleDigitCalculator.ino) is transcribed from the submitted coursework listing. The transcription rejoins wrapped comment lines and preserves the original implementation. The pin numbers use Energia board numbering. Hardware behavior depends on the board package, ADC range, display wiring, and button timing. The archived sketch passed a C++ syntax check with stub declarations for the Energia API. Board-level retesting is pending.
