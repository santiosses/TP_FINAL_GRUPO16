LIST p=16F887
    #include "p16f887.inc"

; ====================================================================
; CONFIGURACIÓN DE FUSES
; ====================================================================
    __CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_ON & _MCLRE_ON & _CP_OFF & _CPD_OFF & _BOREN_ON & _IESO_OFF & _FCMEN_OFF & _LVP_OFF
    __CONFIG _CONFIG2, _BOR4V_BOR40V & _WRT_OFF
    
; ====================================================================
; MAPA DE VARIABLES (Columna 1)
; ====================================================================
D1          EQU 0x20        
D2          EQU 0x21
D3          EQU 0x22
D4          EQU 0x23
INDEX       EQU 0x24
W_TEMP      EQU 0x25        
STATUS_TEMP EQU 0x26

; Variables del Clasificador
BANDERAS    EQU 0x27        ; Bit 0: Flag de Escaneo
VALOR_ADC   EQU 0x28        
CONT_ROJO   EQU 0x29        
CONT_VERDE  EQU 0x2A
CONT_AZUL   EQU 0x2B
SERVO_PULSOS EQU 0x2C       
DEL_REG1    EQU 0x2D        
DEL_REG2    EQU 0x2E

; ====================================================================
; DIRECTIVAS Y ALIAS DE HARDWARE
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
    ORG  0X00          
    GOTO INICIO

; ====================================================================
; VECTOR DE INTERRUPCIÓN (Manejo del Pulsador en RB0 con Antirebote)
; ====================================================================
    ORG  0X04
ISR:
    MOVWF   W_TEMP
    SWAPF   STATUS,0
    MOVWF   STATUS_TEMP
    
    BTFSS   INTCON, INTF
    GOTO    FIN_ISR
    
    BSF     FLAG_ESCANEAR
    BCF     INTCON, INTE        ; ANTIREBOTE: Deshabilita la int. externa temporalmente
    BCF     INTCON, INTF        ; Limpia la bandera de hardware
    
FIN_ISR:
    SWAPF   STATUS_TEMP,0
    MOVWF   STATUS
    SWAPF   W_TEMP,1
    SWAPF   W_TEMP,0
    RETFIE

; ====================================================================
; CONFIGURACIÓN GENERAL DEL MICROCONTROLADOR
; ====================================================================
INICIO:
    ; 1. Configuración Analógica (Banco 3)
    BSF     STATUS, RP1
    BSF     STATUS, RP0         
    CLRF    ANSEL               
    CLRF    ANSELH              
    BSF     ANSEL, 0            

    ; 2. Configuración de Puertos (Banco 1)
    BCF     STATUS, RP1         
    CLRF    TRISD               
    BCF     TRISE, 0            
    BCF     TRISE, 1            
    BSF     TRISA, 0            
    
    MOVLW   B'00000001'         
    MOVWF   TRISB
    
    MOVLW   B'10000001'         
    MOVWF   TRISC

    ; 3. Configuración de Periféricos (Banco 1)
    MOVLW   B'00000000'         
    MOVWF   OPTION_REG
    
    MOVLW   D'25'               
    MOVWF   SPBRG
    BSF     TXSTA, BRGH         
    BSF     TXSTA, TXEN         
    
    MOVLW   B'10000000'         
    MOVWF   ADCON1

    ; 4. Inicialización (Banco 0)
    BCF     STATUS, RP0         
    BCF     STATUS, RP1
    
    CLRF    PORTD
    CLRF    PORTC
    CLRF    BANDERAS
    
    BSF     RCSTA, SPEN         
    BSF     RCSTA, CREN         
    
    MOVLW   B'01000001'         
    MOVWF   ADCON0

    ; 5. Habilitación de Interrupciones
    BSF     INTCON, INTE        
    BSF     INTCON, GIE         

    CALL    LCD_INIT

; ====================================================================
; BUCLE PRINCIPAL
; ====================================================================
LOOP:
    BSF     ADCON0, GO          
ESPERA_ADC:
    BTFSC   ADCON0, GO          
    GOTO    ESPERA_ADC
    MOVF    ADRESH, W
    MOVWF   VALOR_ADC           

    CALL    MOSTRAR_LISTO

    BTFSS   FLAG_ESCANEAR
    GOTO    LOOP                

    ; --- PROCESAMIENTO DE COLOR ---
    BCF     FLAG_ESCANEAR       
    
    CALL    LCD_CLEAR
    CALL    MOSTRAR_ESCANEO     

    ; PASO A: MEDIR ROJO
    BCF     S2
    BCF     S3                  
    CALL    MEDIR_FRECUENCIA
    MOVWF   CONT_ROJO           

    ; PASO B: MEDIR VERDE
    BSF     S2
    BSF     S3                  
    CALL    MEDIR_FRECUENCIA
    MOVWF   CONT_VERDE          

    ; PASO C: MEDIR AZUL
    BCF     S2
    BSF     S3                  
    CALL    MEDIR_FRECUENCIA
    MOVWF   CONT_AZUL           

    ; PASO D: COMPARACIONES LÓGICAS
    MOVF    CONT_VERDE, W
    SUBWF   CONT_ROJO, W        
    BTFSS   STATUS, C           
    GOTO    VERDE_MAYOR

ROJO_MAYOR:
    MOVF    CONT_AZUL, W
    SUBWF   CONT_ROJO, W        
    BTFSS   STATUS, C
    GOTO    ACCION_AZUL
    GOTO    ACCION_ROJO

VERDE_MAYOR:
    MOVF    CONT_AZUL, W
    SUBWF   CONT_VERDE, W       
    BTFSS   STATUS, C
    GOTO    ACCION_AZUL
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
; RUTINA DE SALIDA CON ANTIREBOTE DE SOFTWARE
; ====================================================================
FIN_PROCESO:
ESPERA_SOLTAR:
    BTFSS   PORTB, 0            
    GOTO    ESPERA_SOLTAR       
    
    CALL    DELAY_20MS          
    BCF     INTCON, INTF        
    BSF     INTCON, INTE        
    GOTO    LOOP

; ====================================================================
; SUBRUTINAS TÉCNICAS
; ====================================================================

MEDIR_FRECUENCIA:
    CLRF    TMR1H
    CLRF    TMR1L               
    MOVLW   B'00000111'         
    MOVWF   T1CON
    CALL    DELAY_20MS          
    CLRF    T1CON               
    MOVF    TMR1L, W            
    RETURN

; --- Servomotor ---
SERVO_0_DEG:
    MOVLW   D'50'               
    MOVWF   SERVO_PULSOS
S_0_LP:
    BSF     SERVO_PIN           
    CALL    DELAY_1MS           
    BCF     SERVO_PIN           
    CALL    DELAY_19MS          
    DECFSZ  SERVO_PULSOS, F
    GOTO    S_0_LP
    RETURN

SERVO_90_DEG:
    MOVLW   D'50'
    MOVWF   SERVO_PULSOS
S_90_LP:
    BSF     SERVO_PIN
    CALL    DELAY_1MS
    CALL    DELAY_0_5MS         
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
    CALL    DELAY_2MS           
    BCF     SERVO_PIN
    CALL    DELAY_18MS
    DECFSZ  SERVO_PULSOS, F
    GOTO    S_180_LP
    RETURN

; --- UART ---
UART_TRANSMITIR:
    BTFSS   PIR1, TXIF          
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

; --- LCD Control ---
LCD_INIT:
    CALL    DELAY_20MS
    MOVLW   0x38                
    CALL    LCD_COMANDO
    MOVLW   0x0C                
    CALL    LCD_COMANDO
    CALL    LCD_CLEAR
    RETURN

LCD_CLEAR:
    MOVLW   0x01                
    CALL    LCD_COMANDO
    RETURN

LCD_COMANDO:
    MOVWF   PORTD               
    BCF     LCD_RS              
    BSF     LCD_E               
    NOP
    BCF     LCD_E               
    CALL    DELAY_5MS
    RETURN

LCD_DATOS:
    MOVWF   PORTD               
    BSF     LCD_RS              
    BSF     LCD_E
    NOP
    BCF     LCD_E
    CALL    DELAY_5MS
    RETURN

; --- Textos LCD ---
MOSTRAR_LISTO:
    MOVLW   0x80
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
    RETURN

; --- Delays ---
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

    END