.include "tn2313def.inc"

.macro outi 
	ldi r16,@1 
	out @0,r16 
.endmacro

.cseg


;========================= Таблица прерываний ==========================

.org 0x0000             ; сброс контроллера
	rjmp reset

.org OC0Aaddr           ; переполнение таймера
	rjmp timer0_overflow

.org WDTaddr			; прерывание от wathdog
	rjmp wdt_overflow


;============================ Инициализация ============================
.org 0x0030
reset:

	cli

	; Настраиваем стек
	outi spl, low(ramend)

	; Переключаем делитель на 32
	outi clkpr, 0x80
	outi clkpr, 0x05

	; выбираем режим сна - idle
	outi mcucr, 0x20;0x20

	; включаем пёсика на интервал 16мс
	wdr
	in r16, wdtcsr
	ori r16, 0x18
	out wdtcsr, r16
	;outi wdtcsr, 0x43 ;8Гц
	outi wdtcsr, 0x45 ;2Гц

	; Настраиваем таймер\счетчик (8-битный)
	; WGM=2, COM0A=0, COM0B=0, CS=3 (divide clock on 64, ~18,7kHz)
	; Прерывание таймера будет вызываться с частотой примерно 256Гц
	outi tccr0a, 0x02
	outi tccr0b, 0x02 ;0x03
	outi ocr0a, 73

	; Настраиваем порты ввода\вывода
	; Port B - все на вход с подтяжкой +5в
	; Port D - все на выход, младшие 2 бита - катоды индикаторов = 1
	; Port A - все на выход, младшие 2 бита - аноды индикаторов = 0
	outi ddra, 0xFF
	outi porta, 0x00
	outi ddrb, 0x00
	outi portb, 0xFF
	outi ddrd, 0xFF
	outi portd, 0x03

	clr r0
	clr r1
	clr r2
	clr r4

	; Разрешаем прерывание от таймера
	in r16, timsk
	sbr r16, 1
	out timsk, r16

	sei

;=================== Снимаем показания с порта B ===============
; Результаты замеров помещаются в SRAM, биты на диагонали выставляются в 0
; 0x60-0x67 - прямой массив
; 0x68-0x6F - транспонированный массив
; Замеры производятся следующим образом:
; 1) выставляем 0 на iм выводе порта B
; 2) ждем 20мс
; 3) снимаем показания с порта B
; 4) обнуляем iй бит результатов
; 5) полученный байт записываем в прямой массив
; 6) распихиваем байт побитно в транспонированный массив

start_check_again:

	ldi r20, 0 ; r20 - номер замера
	ldi r21, 1 ; 1 << r20
get_data_loop:

	; выставляем 0 на нужном выводе порта B
	mov r16, r21
	com r16
	out portb, r16
	out ddrb, r21

	; спим 20мс
	rcall delay

	; снимаем показания в регистр r16, убрав из них текущий бит
	in r17, pinb
	com r17
	and r16, r17

	; помещаем их в прямой массив
	ldi xh, 0
	ldi xl, 0x60
	add xl, r20
	st x, r16

	; распихиваем их в транспонированный массив
	ldi r17, 8
	ldi xl, 0x68
transpose_loop:
	ld r18, x
	ror r16
	ror r18
	st x+, r18
	dec r17
	brne transpose_loop

	; убираем 0 с порта B
	outi ddrb, 0x00
	outi portb, 0xFF

	; переходим к следующему замеру
	lsl r21
	inc r20
	cpi r20, 8
	brne get_data_loop


;=================== Ищем короткие замыкания ===================
; при коротком замыкании логическое И строчки массива и строчки
; транспонированного массива не равно 0.

	; строим маску замыканий
	; r17 - счетчик, r18 - маска замыканий
	ldi r17, 8
	eor r18, r18
	ldi xh, 0
	ldi xl, 0x60
	ldi yh, 0
	ldi yl, 0x68
short_circuit_loop:
	lsr r18
	ld r19, x+
	ld r16, y+
	and r16, r19
	breq short_circuit_next
	sbr r18, 0x80
short_circuit_next:
	dec r17
	brne short_circuit_loop

	; если маска замыканий нулевая, то переходим к следующей проверке
	or r18, r18
	breq pos_check

	; иначе преобразуем маску замыканий - если один бит в паре равен 1
	; то заменяем пару на 11 иначе на 00
	ldi r17, 4
	eor r16, r16
short_convert_loop:
	lsl r16
	lsl r16
	rol r18
	brcs short_convert_one
	rol r18
	brcs short_convert_two
	rjmp short_convert_next
short_convert_one:
	rol r18
short_convert_two:
	ori r16, 3
short_convert_next:
	dec r17
	brne short_convert_loop

	; выводим полученную маску на дисплей (быстрое мигание)
	mov r0, r16
	eor r2, r2
	inc r2
	rjmp check_complete


;================ Проверка правильности соединения =============
pos_check:

	; проверка того, что бо\о\бз\з и бс\с\бк\к не перемешаны
	ldi xh, 0
	ldi xl, 0x60
	eor r17, r17
	ldi r18, 4
pos_loop1:
	ld r16, x+
	andi r16, 0xF0
	or r17, r16
	dec r18
	brne pos_loop1
	ldi r18, 4
pos_loop2:
	ld r16, x+
	andi r16, 0x0F
	or r17, r16
	dec r18
	brne pos_loop2
	or r17, r17
	breq pos_no_conflict
	rjmp pos_check_err1

pos_no_conflict:
	; составим два байта, определяющих расположение бо\о\бз\з проводов
	ldi xh, 0
	ldi xl, 0x60
	ld r20, x+
	andi r20, 0x0F
	swap r20
	ld r16, x+
	andi r16, 0x0F
	or r20, r16
	ld r21, x+
	andi r21, 0x0F
	swap r21
	ld r16, x+
	andi r16, 0x0F
	or r21, r16

	; сравним эти байты с эталонными и поместим результат в r22
	cpi r20, 0x64
	brne blk1_m1
	cpi r21, 0x04
	breq blk1_normal
blk1_m1:
	cpi r20, 0xA8
	brne blk1_m2
	cpi r21, 0x80
	breq blk1_left
blk1_m2:
	cpi r20, 0x45
	brne blk1_m3
	cpi r21, 0x04
	breq blk1_right
blk1_m3:
	cpi r20, 0x01
	brne blk1_invalid
	cpi r21, 0x91
	brne blk1_invalid
	; крест
	ldi r22, 0b1011
	rjmp blk1_end
blk1_normal: ; нормально
	ldi r22, 0b0101
	rjmp blk1_end
blk1_left: ; перепутана правая пара
	ldi r22, 0b1001
	rjmp blk1_end
blk1_right: ; перепутана левая пара
	ldi r22, 0b0110
	rjmp blk1_end
blk1_invalid: ; перепутаны обе пары
	ldi r22, 0b1010
	rjmp blk1_end
blk1_end:

	; аналогичная процедура для бк\к\бс\с
	; составим два байта, определяющих расположение проводов
	ld r20, x+
	andi r20, 0xF0
	ld r16, x+
	andi r16, 0xF0
	swap r16
	or r20, r16
	ld r21, x+
	andi r21, 0xF0
	ld r16, x+
	andi r16, 0xF0
	swap r16
	or r21, r16

	; сравним эти байты с эталонными и поместим результат в r23
	cpi r20, 0x01
	brne blk2_m1
	cpi r21, 0xB0
	breq blk2_normal
blk2_m1:
	cpi r20, 0x01
	brne blk2_m2
	cpi r21, 0x07
	breq blk2_left
blk2_m2:
	cpi r20, 0x20
	brne blk2_m3
	cpi r21, 0xB0
	breq blk2_right
blk2_m3:
	cpi r20, 0xE0
	brne blk2_invalid
	cpi r21, 0x04
	brne blk2_invalid
	; крест
	ldi r23, 0b1011
	rjmp blk2_end
blk2_normal: ; нормально
	ldi r23, 0b0101
	rjmp blk2_end
blk2_left: ; перепутана правая пара
	ldi r23, 0b1001
	rjmp blk2_end
blk2_right: ; перепутана левая пара
	ldi r23, 0b0110
	rjmp blk2_end
blk2_invalid: ; перепутаны обе пары
	ldi r23, 0b1010
	rjmp blk2_end
blk2_end:

	; выводим результат	
	swap r23
	or r22, r23
	mov r0, r22
	eor r2, r2
	rjmp drop_check

pos_check_err1:
	; ошибка - перемешаны блоки бо\о\бз\з и бс\с\бк\к, мигаем всеми диодами
	ldi r16, 0b10101010
	mov r0, r16
	eor r2, r2
	rjmp drop_check
	

;====================== Проверка обрывов =======================
; при обрыве логическое ИЛИ строчки массива и строчки транспонированного
; массива равно 0
drop_check:
	; строим маску обрывов
	ldi r17, 8
	eor r18, r18
	ldi xh, 0
	ldi xl, 0x60
	ldi yh, 0
	ldi yl, 0x68
drop_loop:
	lsr r18
	ld r19, x+
	ld r16, y+
	or r16, r19
	brne drop_next
	sbr r18, 0x80
drop_next:
	dec r17
	brne drop_loop

	; если маска обрывов нулевая, то проверка закончена
	or r18, r18
	brne drop_convert
	rjmp check_complete

	; иначе преобразуем маску замыканий - если один бит в паре равен 1
	; то заменяем пару на 11 иначе на 00
drop_convert:
	ldi r17, 4
	eor r16, r16
drop_convert_loop:
	lsl r16
	lsl r16
	rol r18
	brcs drop_convert_one
	rol r18
	brcs drop_convert_two
	rjmp drop_convert_next
drop_convert_one:
	rol r18
drop_convert_two:
	ori r16, 3
drop_convert_next:
	dec r17
	brne drop_convert_loop
	
	; применяем маску к выводимому значению
	com r16
	and r0, r16

	rjmp check_complete

;========== Переход в глубокий сон если нечего показать =======
check_complete:
	wdr
	mov r4, r0
	or r0, r0
	breq sleep_until_wdog
	rjmp start_check_again
sleep_until_wdog:
	outi porta, 0x00
	outi portd, 0x03
	outi mcucr, 0x30 ; power-down
	sleep
	wdr
	rjmp start_check_again

; ====================== Задержка (~5мс) ======================
delay:
	;push r16
	;outi mcucr, 0x20 ; idle
	;pop r16
;	sleep
;	ret
	push r16
	ldi r16, 32
delay_loop:
	dec r16
	brne delay_loop
	pop r16
	ret

;====== Прерывание от таймера для динамической индикации ======
; Байт, выводимый на светодиоды, хранится в регистре r0
; На каждый светодиод отводится 2 бита, означающих:
;   00 - не горит, 01 - горит, 10 - мигание, 11 - мигание в противофазе
; В регистре r2 хранится бит скорости 1 - частое мигание
; Прерывание вызывается с частотой около 256гц
; В регистре r1 хранится счетчик тактов

timer0_overflow:
	push r16
	push r17
	push r18
	push r19
	in r16, sreg
	push r16

	; Увеличиваем счетчик тактов
	inc r1

	; вычисляем текущее состояние мигающих диодов
	; на входе - выводимый байт в r0 и скорость в r2
	; на выходе текущее состояние диодов в r17
	mov r16, r4
	eor r17, r17
	ldi r18, 4
tm_loop1:
	lsl r17
	rol r16
	brcs tm_flash
	rol r16
	brcc tm_next
	inc r17
	rjmp tm_next
tm_flash:
	bst r1, 7
	sbrc r2, 0
	bst r1, 5
	bld r17, 0
	rol r16
	brcc tm_next
	ldi r19, 1
	eor r17, r19
tm_next:
	dec r18
	brne tm_loop1

	; в r17 лежит состояние индикаторов, зажигаем нужные диоды
	; убираем питание с анодов
	outi porta, 0
	; подаем питание на нужный катод
	ldi r16, 1
	sbrs r1, 0
	lsl r16
	out portd, r16
	; подаем питание на нужные аноды
	sbrc r1, 0
	lsr r17
	bst r17, 0
	lsr r17
	bld r17, 0
	andi r17, 3
	out porta, r17

	pop r16
	out sreg, r16
	pop r19
	pop r18
	pop r17
	pop r16

	reti

wdt_overflow:
	reti
