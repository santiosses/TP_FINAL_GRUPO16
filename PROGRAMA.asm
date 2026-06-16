LIST p=16F887
    #include "p16f887.inc"

; ====================================================================
; CONFIGURACIÓN DE FUSES
; ====================================================================
    __CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON & _CP_OFF & _CPD_OFF & _BOREN_ON & _IESO_OFF & _FCMEN_OFF & _LVP_OFF
    __CONFIG _CONFIG2, _BOR4V_BOR40V & _WRT_OFF

; ====================================================================
; MAPA DE VARIABLES
; ====================================================================
D1          EQU 0x20
D2          EQU 0x21
D3          EQU 0x22
D4          EQU 0x23
INDEX       EQU 0x24
W_TEMP      EQU 0x25
STATUS_TEMP EQU 0x26

BANDERAS    EQU 0x27        ; Bit 0: Flag de Escaneo
VALOR_ADC   EQU 0x28
CONT_ROJO   EQU 0x29
CONT_VERDE  EQU 0x2A
CONT_AZUL   EQU 0x2B
SERVO_PULSOS EQU 0x2C
DEL_REG1    EQU 0x2D
DEL_REG2    EQU 0x2E

; ====================================================================
; ALIAS DE HARDWARE
; ====================================================================
#DEFINE FLAG_ESCANEAR BANDERAS,0
#DEFINE LCD_RS        PORTE,0
#DEFINE LCD_E         PORTE,1
#DEFINE S2            PORTB,1
#DEFINE S3            PORTB,2
#DEFINE SERVO_PIN     PORTC,2

; ====================================================================
; VECTOR DE REINICIO
; ====================================================================
    ORG  0x00
    GOTO INICIO

; ====================================================================
; VECTOR DE INTERRUPCIÓN
; ====================================================================
    ORG  0x04
ISR:
    MOVWF   W_TEMP
    SWAPF   STATUS,0
    MOVWF   STATUS_TEMP

    BTFSS   INTCON, INTF
    GOTO    FIN_ISR

    BSF     FLAG_ESCANEAR
    BCF     INTCON, INTE        ; Antirebote: deshabilita int. externa
    BCF     INTCON, INTF        ; Limpia bandera de hardware

FIN_ISR:
    SWAPF   STATUS_TEMP,0
    MOVWF   STATUS
    SWAPF   W_TEMP,1
    SWAPF   W_TEMP,0
    RETFIE

; ====================================================================
; CONFIGURACIÓN GENERAL
; ====================================================================
INICIO:
    ; --- Banco 3: Configuración analógica ---
    BSF     STATUS, RP1
    BSF     STATUS, RP0
    CLRF    ANSEL
    CLRF    ANSELH
    BSF     ANSEL, 0            ; AN0 analógico (potenciómetro en RA0)

    ; --- Banco 1: Dirección de puertos ---
    BCF     STATUS, RP1
    CLRF    TRISD               ; Puerto D salida (datos LCD)
    BCF     TRISE, 0            ; RE0 salida (LCD RS)
    BCF     TRISE, 1            ; RE1 salida (LCD E)
    BSF     TRISA, 0            ; RA0 entrada (ADC)

    MOVLW   B'00000001'         ; RB0=entrada (pulsador), RB1/RB2=salida (S2,S3)
    MOVWF   TRISB

    MOVLW   B'10000001'         ; RC7=entrada (RX UART), RC2=salida (SERVO)
    MOVWF   TRISC

    ; --- OPTION_REG: pull-ups ON, flanco bajada en INT ---
    ; ★ RBPU=0 habilita pull-ups, INTEDG=0 flanco de bajada
    MOVLW   B'00000000'
    MOVWF   OPTION_REG

    ; --- UART: 9600 baud a 4MHz con BRGH=1 ---
    ; SPBRG = (Fosc / (16 * Baud)) - 1 = (4000000 / 153600) - 1 = 25
    MOVLW   D'25'
    MOVWF   SPBRG
    BSF     TXSTA, BRGH
    BSF     TXSTA, TXEN

    ; --- Banco 0: Inicialización de registros ---
    BCF     STATUS, RP0
    BCF     STATUS, RP1

    CLRF    PORTD
    CLRF    PORTC
    CLRF    PORTE               ; ★ Limpia PORTE (RS y E del LCD en 0)
    CLRF    BANDERAS

    BSF     RCSTA, SPEN         ; Habilita módulo serial
    BSF     RCSTA, CREN         ; Habilita recepción continua

    ; ★ ADCON1 va en Banco 0 en el PIC16F887
    ; Justificado a la derecha, Vref = VDD/GND
    MOVLW   B'10000000'
    MOVWF   ADCON1

    ; ADCON0: canal AN0, ADC encendido
    MOVLW   B'01000001'
    MOVWF   ADCON0

    ; --- Habilitación de interrupciones ---
    BSF     INTCON, INTE        ; Habilita interrupción externa RB0
    BSF     INTCON, GIE         ; Habilita interrupciones globales

    ; ★ Delay extra para estabilizar alimentación antes del LCD
    CALL    DELAY_20MS
    CALL    DELAY_20MS

    CALL    LCD_INIT

; ====================================================================
; BUCLE PRINCIPAL
; ====================================================================
LOOP:
    ; --- Leer ADC (potenciómetro) ---
    BSF     ADCON0, GO
ESPERA_ADC:
    BTFSC   ADCON0, GO
    GOTO    ESPERA_ADC
    MOVF    ADRESH, W
    MOVWF   VALOR_ADC           ; Guarda valor (puede usarse para umbral futuro)

    CALL    MOSTRAR_LISTO       ; Muestra "SISTEMA LISTO" en LCD línea 1

    BTFSS   FLAG_ESCANEAR
    GOTO    LOOP

    ; --- Inicio de escaneo ---
    BCF     FLAG_ESCANEAR

    CALL    LCD_CLEAR
    CALL    MOSTRAR_ESCANEO     ; ★ Muestra "ESCANEANDO..." mientras mide

    ; PASO A: Medir componente ROJA (S2=0, S3=0)
    BCF     S2
    BCF     S3
    CALL    DELAY_1MS           ; ★ Pequeño delay para estabilizar el sensor
    CALL    MEDIR_FRECUENCIA
    MOVWF   CONT_ROJO

    ; PASO B: Medir componente VERDE (S2=1, S3=1)
    BSF     S2
    BSF     S3
    CALL    DELAY_1MS
    CALL    MEDIR_FRECUENCIA
    MOVWF   CONT_VERDE

    ; PASO C: Medir componente AZUL (S2=0, S3=1)
    BCF     S2
    BSF     S3
    CALL    DELAY_1MS
    CALL    MEDIR_FRECUENCIA
    MOVWF   CONT_AZUL

    ; ====================================================================
    ; Telemetría de Debug Serial (Envía los datos crudos a la PC)
    ; ====================================================================
    MOVLW   'R'
    CALL    UART_TRANSMITIR
    MOVLW   ':'
    CALL    UART_TRANSMITIR
    MOVF    CONT_ROJO, W
    CALL    ENVIAR_BYTE_DECIMAL ; Envía por ejemplo "R:145"

    MOVLW   ' '
    CALL    UART_TRANSMITIR    ; Espacio de separación

    MOVLW   'V'
    CALL    UART_TRANSMITIR
    MOVLW   ':'
    CALL    UART_TRANSMITIR
    MOVF    CONT_VERDE, W
    CALL    ENVIAR_BYTE_DECIMAL ; Envía por ejemplo "V:082"

    MOVLW   ' '
    CALL    UART_TRANSMITIR    ; Espacio de separación

    MOVLW   'A'
    CALL    UART_TRANSMITIR
    MOVLW   ':'
    CALL    UART_TRANSMITIR
    MOVF    CONT_AZUL, W
    CALL    ENVIAR_BYTE_DECIMAL ; Envía por ejemplo "A:034"

    MOVLW   0x0D                ; Retorno de carro (Enter)
    CALL    UART_TRANSMITIR
    MOVLW   0x0A                ; Salto de línea
    CALL    UART_TRANSMITIR
    
    ; ★ PASO D: Comparación corregida
    ; El TCS3200 genera MÁS frecuencia para el color que más detecta.
    ; Queremos encontrar cuál de los tres contadores es el MAYOR.
    ; SUBWF hace: W = destino - W  (o sea: resultado = segundo - primero)
    ; Si CONT_ROJO >= CONT_VERDE  → borrow=0 → Carry=1 → BTFSS STATUS,C salta

    ; ¿Es ROJO >= VERDE?
    MOVF    CONT_VERDE, W
    SUBWF   CONT_ROJO, W        ; W = CONT_ROJO - CONT_VERDE
    BTFSS   STATUS, C           ; Si Carry=1: ROJO >= VERDE → ROJO_MAYOR
    GOTO    VERDE_MAYOR_QUE_ROJO

ROJO_GTE_VERDE:
    ; ¿Es ROJO >= AZUL?
    MOVF    CONT_AZUL, W
    SUBWF   CONT_ROJO, W        ; W = CONT_ROJO - CONT_AZUL
    BTFSS   STATUS, C           ; Si Carry=1: ROJO >= AZUL → ROJO es mayor
    GOTO    ACCION_AZUL         ; Si no: AZUL > ROJO (y AZUL > VERDE porque llegamos acá)
    GOTO    ACCION_ROJO

VERDE_MAYOR_QUE_ROJO:
    ; ¿Es VERDE >= AZUL?
    MOVF    CONT_AZUL, W
    SUBWF   CONT_VERDE, W       ; W = CONT_VERDE - CONT_AZUL
    BTFSS   STATUS, C           ; Si Carry=1: VERDE >= AZUL → VERDE es mayor
    GOTO    ACCION_AZUL         ; Si no: AZUL es el mayor
    GOTO    ACCION_VERDE

; ====================================================================
; BLOQUES DE ACCIÓN
; ====================================================================
ACCION_ROJO:
    CALL    LCD_CLEAR
    CALL    TXT_LCD_ROJO
    CALL    UART_ENVIA_R
    CALL    SERVO_0_DEG
    GOTO    FIN_PROCESO

ACCION_VERDE:
    CALL    LCD_CLEAR
    CALL    TXT_LCD_VERDE
    CALL    UART_ENVIA_V
    CALL    SERVO_90_DEG
    GOTO    FIN_PROCESO

ACCION_AZUL:
    CALL    LCD_CLEAR
    CALL    TXT_LCD_AZUL
    CALL    UART_ENVIA_A
    CALL    SERVO_180_DEG
    GOTO    FIN_PROCESO

; ====================================================================
; FIN DE PROCESO — Antirebote de software
; ====================================================================
FIN_PROCESO:
    ; Espera a que se suelte el pulsador (activo bajo con pull-up)
ESPERA_SOLTAR:
    BTFSS   PORTB, 0            ; Si RB0=1 (suelto) → salta y sale
    GOTO    ESPERA_SOLTAR       ; Si RB0=0 (presionado) → sigue esperando

    CALL    DELAY_20MS          ; Delay antirebote al soltar
    BCF     INTCON, INTF        ; Limpia cualquier bandera espuria
    BSF     INTCON, INTE        ; Re-habilita interrupción externa
    GOTO    LOOP

; ====================================================================
; SUBRUTINA: MEDIR FRECUENCIA (Timer1 como contador externo) — CORREGIDA
; ====================================================================
MEDIR_FRECUENCIA:
    CLRF    TMR1H
    CLRF    TMR1L    
    ; Cambiamos el último bit a 1 (B'00000111') para encender el Timer1 (TMR1ON = 1)
    MOVLW   B'00000111'   
    MOVWF   T1CON    
    CALL    DELAY_20MS          ; Ventana de conteo de 20ms    
    CLRF    T1CON               ; Detiene el Timer1 apagando el bit
    MOVF    TMR1L, W            ; Lee el byte bajo (suficiente para comparar)
    RETURN

; ====================================================================
; SUBRUTINAS DE SERVO (50 pulsos = ~1 segundo de movimiento sostenido)
; ====================================================================
SERVO_0_DEG:
    MOVLW   D'50'
    MOVWF   SERVO_PULSOS
S_0_LP:
    BSF     SERVO_PIN
    CALL    DELAY_1MS           ; Pulso de 1ms → 0°
    BCF     SERVO_PIN
    CALL    DELAY_19MS          ; Periodo total 20ms
    DECFSZ  SERVO_PULSOS, F
    GOTO    S_0_LP
    RETURN

SERVO_90_DEG:
    MOVLW   D'50'
    MOVWF   SERVO_PULSOS
S_90_LP:
    BSF     SERVO_PIN
    CALL    DELAY_1MS
    CALL    DELAY_0_5MS         ; Pulso de 1.5ms → 90°
    BCF     SERVO_PIN
    CALL    DELAY_18_5MS
    DECFSZ  SERVO_PULSOS, F
    GOTO    S_90_LP
    RETURN

SERVO_180_DEG:
    MOVLW   D'50'
    MOVWF   SERVO_PULSOS
S_180_LP:
    BSF     SERVO_PIN
    CALL    DELAY_2MS           ; Pulso de 2ms → 180°
    BCF     SERVO_PIN
    CALL    DELAY_18MS
    DECFSZ  SERVO_PULSOS, F
    GOTO    S_180_LP
    RETURN

; ====================================================================
; SUBRUTINAS UART
; ====================================================================
UART_TRANSMITIR:
    BTFSS   PIR1, TXIF          ; Espera a que el buffer esté libre
    GOTO    UART_TRANSMITIR
    MOVWF   TXREG
    RETURN

UART_ENVIA_R:
    MOVLW   'R'
    CALL    UART_TRANSMITIR
    MOVLW   'O'
    CALL    UART_TRANSMITIR
    MOVLW   'J'
    CALL    UART_TRANSMITIR
    MOVLW   'O'
    CALL    UART_TRANSMITIR
    MOVLW   0x0D
    CALL    UART_TRANSMITIR
    MOVLW   0x0A
    CALL    UART_TRANSMITIR
    RETURN

UART_ENVIA_V:
    MOVLW   'V'
    CALL    UART_TRANSMITIR
    MOVLW   'E'
    CALL    UART_TRANSMITIR
    MOVLW   'R'
    CALL    UART_TRANSMITIR
    MOVLW   'D'
    CALL    UART_TRANSMITIR
    MOVLW   'E'
    CALL    UART_TRANSMITIR
    MOVLW   0x0D
    CALL    UART_TRANSMITIR
    MOVLW   0x0A
    CALL    UART_TRANSMITIR
    RETURN

UART_ENVIA_A:
    MOVLW   'A'
    CALL    UART_TRANSMITIR
    MOVLW   'Z'
    CALL    UART_TRANSMITIR
    MOVLW   'U'
    CALL    UART_TRANSMITIR
    MOVLW   'L'
    CALL    UART_TRANSMITIR
    MOVLW   0x0D
    CALL    UART_TRANSMITIR
    MOVLW   0x0A
    CALL    UART_TRANSMITIR
    RETURN

; ====================================================================
; SUBRUTINAS LCD (interfaz 8 bits, HD44780)
; ====================================================================

; ★ LCD_INIT corregida: secuencia completa HD44780
LCD_INIT:
    CALL    DELAY_20MS          ; Espera 20ms tras encendido
    MOVLW   0x38                ; Function Set: 8 bits, 2 líneas, 5x8
    CALL    LCD_COMANDO
    CALL    DELAY_5MS           ; ★ Delay requerido entre los primeros 0x38
    MOVLW   0x38                ; Segunda vez
    CALL    LCD_COMANDO
    CALL    DELAY_1MS
    MOVLW   0x38                ; Tercera vez (ahora el LCD está sincronizado)
    CALL    LCD_COMANDO
    MOVLW   0x0C                ; Display ON, cursor OFF, blink OFF
    CALL    LCD_COMANDO
    MOVLW   0x01                ; Clear display
    CALL    LCD_COMANDO
    CALL    DELAY_5MS           ; ★ Clear necesita >1.64ms
    MOVLW   0x06                ; ★ Entry mode: incrementa cursor, no desplaza
    CALL    LCD_COMANDO
    RETURN

LCD_CLEAR:
    MOVLW   0x01
    CALL    LCD_COMANDO
    CALL    DELAY_5MS           ; ★ Delay obligatorio después de Clear
    RETURN

LCD_COMANDO:
    MOVWF   PORTD
    BCF     LCD_RS              ; RS=0 → comando
    NOP                         ; ★ Setup time antes de E
    BSF     LCD_E
    NOP                         ; ★ Enable pulse width mínimo ~230ns
    NOP
    BCF     LCD_E
    CALL    DELAY_5MS           ; Espera ejecución del comando
    RETURN

LCD_DATOS:
    MOVWF   PORTD
    BSF     LCD_RS              ; RS=1 → dato
    NOP
    BSF     LCD_E
    NOP
    NOP
    BCF     LCD_E
    CALL    DELAY_1MS           ; Los datos necesitan menos tiempo que comandos
    RETURN

; ====================================================================
; TEXTOS LCD
; ====================================================================
MOSTRAR_LISTO:
    MOVLW   0x80                ; Línea 1, posición 0
    CALL    LCD_COMANDO
    MOVLW   'S'
    CALL    LCD_DATOS
    MOVLW   'I'
    CALL    LCD_DATOS
    MOVLW   'S'
    CALL    LCD_DATOS
    MOVLW   'T'
    CALL    LCD_DATOS
    MOVLW   'E'
    CALL    LCD_DATOS
    MOVLW   'M'
    CALL    LCD_DATOS
    MOVLW   'A'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   'L'
    CALL    LCD_DATOS
    MOVLW   'I'
    CALL    LCD_DATOS
    MOVLW   'S'
    CALL    LCD_DATOS
    MOVLW   'T'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    ; ★ Segunda línea: instrucción de uso
    MOVLW   0xC0                ; Línea 2, posición 0
    CALL    LCD_COMANDO
    MOVLW   'P'
    CALL    LCD_DATOS
    MOVLW   'U'
    CALL    LCD_DATOS
    MOVLW   'L'
    CALL    LCD_DATOS
    MOVLW   'S'
    CALL    LCD_DATOS
    MOVLW   'A'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   'P'
    CALL    LCD_DATOS
    MOVLW   '/'
    CALL    LCD_DATOS
    MOVLW   'E'
    CALL    LCD_DATOS
    MOVLW    'S'
    CALL    LCD_DATOS
    MOVLW   'C'
    CALL    LCD_DATOS
    MOVLW   'A'
    CALL    LCD_DATOS
    MOVLW   'N'
    CALL    LCD_DATOS
    RETURN

MOSTRAR_ESCANEO:
    MOVLW   0x80
    CALL    LCD_COMANDO
    MOVLW   'E'
    CALL    LCD_DATOS
    MOVLW   'S'
    CALL    LCD_DATOS
    MOVLW   'C'
    CALL    LCD_DATOS
    MOVLW   'A'
    CALL    LCD_DATOS
    MOVLW   'N'
    CALL    LCD_DATOS
    MOVLW   'E'
    CALL    LCD_DATOS
    MOVLW   'A'
    CALL    LCD_DATOS
    MOVLW   'N'
    CALL    LCD_DATOS
    MOVLW   'D'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   '.'
    CALL    LCD_DATOS
    MOVLW   '.'
    CALL    LCD_DATOS
    MOVLW   '.'
    CALL    LCD_DATOS
    RETURN

TXT_LCD_ROJO:
    MOVLW   0x80
    CALL    LCD_COMANDO
    MOVLW   'C'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   'L'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   ':'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   'J'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    ; Segunda línea: posición servo
    MOVLW   0xC0
    CALL    LCD_COMANDO
    MOVLW   'S'
    CALL    LCD_DATOS
    MOVLW   'E'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   'V'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   ':'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   '0'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   'G'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   'A'
    CALL    LCD_DATOS
    MOVLW   'D'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   'S'
    CALL    LCD_DATOS
    RETURN

TXT_LCD_VERDE:
    MOVLW   0x80
    CALL    LCD_COMANDO
    MOVLW   'C'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   'L'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   ':'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   'V'
    CALL    LCD_DATOS
    MOVLW   'E'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   'D'
    CALL    LCD_DATOS
    MOVLW   'E'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   0xC0
    CALL    LCD_COMANDO
    MOVLW   'S'
    CALL    LCD_DATOS
    MOVLW   'E'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   'V'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   ':'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   '9'
    CALL    LCD_DATOS
    MOVLW   '0'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   'G'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   'A'
    CALL    LCD_DATOS
    MOVLW   'D'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    RETURN

TXT_LCD_AZUL:
    MOVLW   0x80
    CALL    LCD_COMANDO
    MOVLW   'C'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   'L'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   ':'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   'A'
    CALL    LCD_DATOS
    MOVLW   'Z'
    CALL    LCD_DATOS
    MOVLW   'U'
    CALL    LCD_DATOS
    MOVLW   'L'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   0xC0
    CALL    LCD_COMANDO
    MOVLW   'S'
    CALL    LCD_DATOS
    MOVLW   'E'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   'V'
    CALL    LCD_DATOS
    MOVLW   'O'
    CALL    LCD_DATOS
    MOVLW   ':'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   '1'
    CALL    LCD_DATOS
    MOVLW   '8'
    CALL    LCD_DATOS
    MOVLW   '0'
    CALL    LCD_DATOS
    MOVLW   ' '
    CALL    LCD_DATOS
    MOVLW   'G'
    CALL    LCD_DATOS
    MOVLW   'R'
    CALL    LCD_DATOS
    MOVLW   'A'
    CALL    LCD_DATOS
    MOVLW   'D'
    CALL    LCD_DATOS
    RETURN

; ====================================================================
; DELAYS (a 4MHz: 1 ciclo = 1us, 1 instrucción = ~1us)
; ====================================================================
DELAY_0_5MS:
    MOVLW   D'165'
    MOVWF   DEL_REG1
DL_05:
    DECFSZ  DEL_REG1, F
    GOTO    DL_05
    RETURN

DELAY_1MS:
    CALL    DELAY_0_5MS
    CALL    DELAY_0_5MS
    RETURN

DELAY_2MS:
    CALL    DELAY_1MS
    CALL    DELAY_1MS
    RETURN

DELAY_5MS:
    MOVLW   D'5'
    MOVWF   DEL_REG2
DL_5:
    CALL    DELAY_1MS
    DECFSZ  DEL_REG2, F
    GOTO    DL_5
    RETURN

DELAY_18MS:
    CALL    DELAY_5MS
    CALL    DELAY_5MS
    CALL    DELAY_5MS
    CALL    DELAY_2MS
    CALL    DELAY_1MS
    RETURN

DELAY_18_5MS:
    CALL    DELAY_18MS
    CALL    DELAY_0_5MS
    RETURN

DELAY_19MS:
    CALL    DELAY_18MS
    CALL    DELAY_1MS
    RETURN

DELAY_20MS:
    CALL    DELAY_19MS
    CALL    DELAY_1MS
    RETURN
; ====================================================================
; SUBRUTINA: ENVIAR BYTE EN FORMATO DECIMAL (000 al 255) POR UART
; ====================================================================
ENVIAR_BYTE_DECIMAL:
    MOVWF   D4                  ; Guardamos una copia del valor original
    CLRF    D1                  ; Contador de Centenas = 0
    CLRF    D2                  ; Contador de Decenas = 0

C_CENTENAS:
    MOVLW   D'100'
    SUBWF   D4, W               ; W = D4 - 100
    BTFSS   STATUS, C           ; ¿El resultado fue negativo? (D4 < 100)
    GOTO    C_DECENAS           ; Sí -> Pasamos a las decenas
    MOVWF   D4                  ; No -> Guardamos la resta en D4
    INCF    D1, F               ; Incrementamos las centenas
    GOTO    C_CENTENAS          ; Repetimos

C_DECENAS:
    MOVLW   D'10'
    SUBWF   D4, W               ; W = D4 - 10
    BTFSS   STATUS, C           ; ¿El resultado fue negativo? (D4 < 10)
    GOTO    C_UNIDADES          ; Sí -> Lo que queda son las unidades
    MOVWF   D4                  ; No -> Guardamos la resta en D4
    INCF    D2, F               ; Incrementamos las decenas
    GOTO    C_DECENAS           ; Repetimos

C_UNIDADES:
    MOVF    D4, W
    MOVWF   D3                  ; Unidades = Lo que quedó en D4

    ; --- Enviamos los 3 dígitos por UART transmutados a ASCII ---
    MOVLW   0x30                ; Convertir a número ASCII ('0' = 0x30)
    ADDWF   D1, W               ; W = Centenas + '0'
    CALL    UART_TRANSMITIR

    MOVLW   0x30
    ADDWF   D2, W               ; W = Decenas + '0'
    CALL    UART_TRANSMITIR

    MOVLW   0x30
    ADDWF   D3, W               ; W = Unidades + '0'
    CALL    UART_TRANSMITIR
    RETURN
    END
