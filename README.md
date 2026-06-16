markdown_content = """# Sistema Clasificador e Indicador de Color

> **Asignatura:** Electrónica Digital II - Universidad Nacional de Córdoba
> **Integrantes:** 

---

## 1. Descripción General del Proyecto

El presente proyecto consiste en el diseño e implementación de un sistema clasificador de colores basado en microcontrolador. El objetivo principal es detectar el color de un objeto expuesto al sensor y comunicarlo de múltiples formas para garantizar una lectura clara del entorno. El sistema está pensado para aplicaciones industriales a escala, procesos de selección de materiales o fines didácticos, resolviendo la necesidad de automatizar el reconocimiento visual de piezas.

Para su funcionamiento, el sistema se mantiene a la espera de una señal de inicio generada por un pulsador. Una vez activado, el sensor óptico realiza la lectura, el microcontrolador procesa la señal y expone el resultado en una pantalla LCD local, transmite el dato hacia una computadora mediante comunicación serie (USB-UART) y posiciona un servomotor en un ángulo específico, funcionando como un indicador analógico tipo tacómetro. Adicionalmente, se integra la lectura de un potenciómetro a través del conversor analógico-digital (ADC) como requerimiento funcional de la etapa de acondicionamiento de señales.

### Alcances del Proyecto

* **El sistema SÍ es capaz de:**
  * Iniciar el proceso de sensado únicamente bajo demanda del usuario mediante una interrupción o lectura de un botón físico.
  * Identificar colores utilizando el módulo sensor TCS230 / TCS3200.
  * Transmitir el color detectado en tiempo real a una terminal de PC mediante el protocolo UART.
  * Mostrar la información de manera local en un display alfanumérico LCD 16x2.
  * Posicionar un servomotor en ángulos predeterminados según el color detectado.
  * Adquirir e interpretar variaciones de tensión analógica provenientes de un potenciómetro externo.

* **El sistema NO incluye:**
  * Almacenamiento local de datos (Data Logging) en memorias EEPROM externas o tarjetas SD.
  * Conectividad inalámbrica (Wi-Fi o Bluetooth).
  * Control de velocidad dinámico sobre cintas transportadoras reales.

### Posibles Etapas Siguientes

* Migrar el circuito de simulación y protoboard a un circuito impreso (PCB) diseñado bajo normas de ruteo para señales mixtas.
* Desarrollar una interfaz gráfica (GUI) en Python para la computadora, reemplazando la terminal de texto genérica por un panel de control interactivo.
* Incorporar una rutina de calibración automática inicial para compensar las condiciones de iluminación del entorno.

---

## 2. Arquitectura del Sistema: Hardware y Software

### Hardware e Interconexión

* **Microcontrolador Central:** Microchip PIC16F887.
* **Sensor de Color:** Módulo TCS230 / TCS3200 acoplado a los pines digitales para la lectura de frecuencia.
* **Interfaz de Usuario (Local):** Display LCD 16x2 (LM016L) manejado mediante un bus de datos paralelo.
* **Actuador Indicador:** Servomotor controlado por señal PWM.
* **Entradas de Control:** Pulsadores con resistencias pull-up/pull-down para el inicio de sensado y reset del sistema (MCLR). Potenciómetro de 10k conectado a un canal analógico (AN).
* **Comunicación:** Interfaz UART conectada a pines de transmisión y recepción (TX/RX) para el enlace con la PC.

### Arquitectura de Software (Firmware)

El firmware fue estructurado bajo un modelo de lazo de control principal (Super Loop) asistido por interrupciones. El flujo general es el siguiente:
1. Inicialización de puertos, periféricos (ADC, PWM, UART) y pantalla LCD.
2. Estado de reposo esperando el flanco de activación en el botón de inicio.
3. Al detectarse el pulso, se activa la lectura secuencial de los fotodiodos del sensor (rojo, verde, azul).
4. Se realiza la conversión ADC del potenciómetro.
5. Se procesan los datos para determinar el color predominante.
6. Se formatea la cadena de caracteres y se envía por el puerto serie.
7. Se actualiza el buffer del display LCD.
8. Se ajusta el ciclo de trabajo (Duty Cycle) del PWM para rotar el servomotor al ángulo correspondiente.

---

## 3. Especificaciones Eléctricas, Alimentación y Entorno

### Parámetros de Alimentación

* **Tensión de operación del sistema:** 5V DC.
* **Método de alimentación:** Regulador lineal o alimentación directa desde el puerto USB de la computadora.
* **Señal de Reloj:** Oscilador de cristal externo.

### Entorno de Desarrollo (Electrónica Digital II)

* **Herramientas de Software:** MPLAB X IDE y compilador XC8. Simulación en Proteus.
* **Configuración de Bits (Fuses Críticos):**
  * *Oscilador:* HS (Cristal externo).
  * *Watchdog Timer (WDT):* OFF.
  * *Master Clear (MCLRE):* ON (Vinculado a botón de reset en pin RE3).
* **Periféricos Internos Utilizados:**
  * Módulo ADC: Para la lectura del potenciómetro.
  * Módulo EUSART: Para la transmisión de datos a la computadora.
  * Módulo CCP (PWM): Para la generación de la señal de control del servomotor.
  * Timers: Para la lectura de la frecuencia proveniente del sensor TCS3200 y la temporización general.

---

## 4. Proceso de Integración y Desarrollo

El proyecto se desarrolló siguiendo un enfoque modular, validando cada subsistema por separado antes de la integración final:

* **Etapa 1 (Control Base):** Configuración del oscilador, pines de entrada/salida y validación de retardos. 
* **Etapa 2 (Visualización):** Implementación de la librería del LCD 16x2 y pruebas de impresión de caracteres.
* **Etapa 3 (Adquisición Analógica):** Configuración del módulo ADC, lectura del potenciómetro y mapeo de variables.
* **Etapa 4 (Comunicación):** Configuración del módulo EUSART y envío de cadenas de texto hacia la terminal virtual.
* **Etapa 5 (Actuación):** Generación de la señal PWM y caracterización de los ángulos del servomotor según el ancho de pulso.
* **Etapa 6 (Sensor e Integración Final):** Incorporación del algoritmo de lectura del sensor TCS3200, lógica de decisión de color e integración de todos los periféricos activados mediante el botón de inicio.

---

## 5. Ensayos, Pruebas y Resultados

El sistema fue sometido a pruebas exhaustivas en entornos de simulación (Proteus) para verificar el correcto flujo de las señales antes del montaje físico.

* **Validación de Señales:** Se utilizó instrumentación virtual (osciloscopio) para corroborar la correcta forma de onda de la señal PWM entregada al servomotor y las tramas de datos digitales enviadas por el pin TX del UART.
* **Interacción Dinámica:** Se comprobó que el sistema permanece en reposo absoluto hasta recibir el estímulo del botón principal, tras lo cual la terminal serie y el LCD reflejan sincrónicamente la información del color emulado.

---

## 6. Estructura del Repositorio
