# ================================================================
# BATTLE CITY - Nivel 1 con tanque jugador y el primer enemigo
# Arquitectura: RISC-V (RARS)
#
# Configuracion del Bitmap Display:
#   Unit Width in Pixels:  8
#   Unit Height in Pixels: 8
#   Display Width:         64
#   Display Height:        64
#   Base address:          gp
#
# Controles:
#   W A S D = mover / girar el tanque azul
#   Espacio = disparar (un proyectil propio a la vez)
#
# ----------------------------------------------------------------
# IDEA GENERAL (tres capas, igual que un motor de juego real)
#
#   1) MODELO   mapa_terreno  -> el escenario, un color por pixel
#               tanque_*      -> registros con el estado de cada tanque
#               bala_*        -> registros con el estado de cada disparo
#
#   2) LOGICA   procesar_entrada / actualizar_enemigo / actualizar_balas
#               leen y modifican SOLO el modelo, nunca la pantalla.
#
#   3) VISTA    dibujar_escena compone terreno, tanques y balas en un
#               buffer invisible; solo entonces presenta el cuadro entero.
#
# Gracias a esa separacion no hay que "borrar" sprites a mano: cada
# cuadro la pantalla se reconstruye completa a partir del modelo.
#
# ----------------------------------------------------------------
# CONVENCIONES DE LLAMADA USADAS EN TODO EL ARCHIVO
#   a0..a5 = parametros de entrada, a0 = valor de retorno
#   t0..t6 = temporales, se pueden perder en cualquier llamada
#   s0..s2 = valores que deben sobrevivir a una llamada (se apilan)
#   Cada funcion que llama a otra guarda ra al entrar y lo restaura
#   al salir; las funciones hoja (sin jal dentro) no tocan la pila.
# ================================================================


# ================================================================
# 1. CONSTANTES
# ================================================================

# --- Pantalla ---
.eqv SCREEN_WIDTH   64
.eqv SCREEN_HEIGHT  64
.eqv TOTAL_PIXELES  4096          # 64 * 64

# --- Teclado mapeado a memoria (MMIO) ---
.eqv KEY_STATUS_ADDRESS 0xFFFF0000
.eqv KEY_INPUT_ADDRESS  0xFFFF0004

# --- Teclas (ASCII en minuscula) ---
.eqv ASCII_W        119
.eqv ASCII_S        115
.eqv ASCII_A        97
.eqv ASCII_D        100
.eqv ASCII_ESPACIO  32

# --- Colores 0x00RRGGBB ---
.eqv COLOR_NEGRO            0x00000000
.eqv COLOR_BLANCO           0x00FFFFFF
.eqv COLOR_ROJO             0x00FF0000
.eqv COLOR_LADRILLO         0x00E86F00
.eqv COLOR_ACERO            0x00B0B0B0
.eqv COLOR_AGUA             0x000066CC
.eqv COLOR_BASE             0x00FFD000
.eqv COLOR_ORUGA            0x00404040
.eqv COLOR_JUGADOR_CUERPO   0x000000FF
.eqv COLOR_JUGADOR_CANON    0x00FFFFFF
.eqv COLOR_ENEMIGO_CUERPO   0x00E0E0E0
.eqv COLOR_ENEMIGO_CANON    0x00FF3030

# --- Direcciones (sirven de indice en las tablas) ---
.eqv DIR_ARRIBA     0
.eqv DIR_ABAJO      1
.eqv DIR_IZQUIERDA  2
.eqv DIR_DERECHA    3

# --- Campos del registro "tanque" (desplazamientos en bytes) ---
.eqv T_X                0
.eqv T_Y                4
.eqv T_DIR              8
.eqv T_VIVO             12
.eqv T_COLOR_CUERPO     16
.eqv T_COLOR_CANON      20
.eqv T_RETARDO_MOV      24        # cuadros que faltan para el proximo paso
.eqv T_PERIODO_MOV      28        # cuadros entre paso y paso
.eqv T_RETARDO_DISPARO  32
.eqv T_PERIODO_DISPARO  36

# --- Campos del registro "bala" ---
.eqv B_ACTIVA   0
.eqv B_X        4
.eqv B_Y        8
.eqv B_DIR      12
.eqv B_DUENO    16
.eqv DUENO_JUGADOR  0
.eqv DUENO_ENEMIGO  1

# --- Tamanos y ritmo del juego ---
.eqv TANQUE_TAM             5     # el tanque ocupa 5x5 pixeles
.eqv BLOQUE_TAM             20    # 5 palabras por fila de nivel_1_bloques
.eqv CUADRO_MS              16    # duracion de un cuadro (~60 por segundo)
.eqv JUGADOR_PASOS_POR_EVENTO 2   # avance por cada evento del auto-repeat
.eqv BALA_PASOS_POR_CUADRO  2     # pixeles que avanza una bala por cuadro
.eqv ENEMIGO_CUADROS_PASO   3     # un paso del enemigo cada 3 cuadros
.eqv ENEMIGO_CUADROS_TIRO   55    # dispara aproximadamente cada segundo
.eqv ENEMIGO_PROB_GIRO      24    # 1 de cada 24 pasos cambia de rumbo
.eqv JUGADOR_X_INICIAL      30
.eqv JUGADOR_Y_INICIAL      30
.eqv ENEMIGO_X_INICIAL      0
.eqv ENEMIGO_Y_INICIAL      0

# --- Base (aguila) que hay que defender ---
.eqv BASE_X      30
.eqv BASE_Y      58
.eqv BASE_ANCHO  4
.eqv BASE_ALTO   5


# ================================================================
# 2. DATOS
# ================================================================
.data
.align 2

# ---- Modelo y cuadro oculto: un color por pixel (64 * 64 * 4 bytes) ----
mapa_terreno: .space 16384
buffer_frame: .space 16384

# ---- Estado de la partida ----
partida_terminada: .word 0

# ---- Ultima posicion dibujada: x, y, visible ----
# Permite restaurar solo las zonas ocupadas por sprites, no los 4096 pixeles.
render_jugador:      .word 0, 0, 0
render_enemigo:      .word 0, 0, 0
render_bala_jugador: .word 0, 0, 0
render_bala_enemigo: .word 0, 0, 0

mensaje_base:     .asciz "Base destruida. Fin de la partida.\n"
.align 2

# ---- Tanques: mismo formato de registro para jugador y enemigo ----
tanque_jugador:
    .word JUGADOR_X_INICIAL       # T_X
    .word JUGADOR_Y_INICIAL       # T_Y
    .word DIR_ARRIBA              # T_DIR
    .word 1                       # T_VIVO
    .word COLOR_JUGADOR_CUERPO    # T_COLOR_CUERPO
    .word COLOR_JUGADOR_CANON     # T_COLOR_CANON
    .word 0                       # T_RETARDO_MOV      (lo mueve el teclado)
    .word 0                       # T_PERIODO_MOV
    .word 0                       # T_RETARDO_DISPARO  (dispara el teclado)
    .word 0                       # T_PERIODO_DISPARO

tanque_enemigo:
    .word ENEMIGO_X_INICIAL       # T_X
    .word ENEMIGO_Y_INICIAL       # T_Y
    .word DIR_ABAJO               # T_DIR
    .word 1                       # T_VIVO
    .word COLOR_ENEMIGO_CUERPO    # T_COLOR_CUERPO
    .word COLOR_ENEMIGO_CANON     # T_COLOR_CANON
    .word ENEMIGO_CUADROS_PASO    # T_RETARDO_MOV
    .word ENEMIGO_CUADROS_PASO    # T_PERIODO_MOV
    .word ENEMIGO_CUADROS_TIRO    # T_RETARDO_DISPARO
    .word ENEMIGO_CUADROS_TIRO    # T_PERIODO_DISPARO

# ---- Balas: cada bando tiene un unico proyectil en vuelo ----
bala_jugador:
    .word 0, 0, 0, 0, DUENO_JUGADOR
bala_enemigo:
    .word 0, 0, 0, 0, DUENO_ENEMIGO

# ---- Tabla de direcciones: evita cadenas de comparaciones ----
#      indice = DIR_ARRIBA, DIR_ABAJO, DIR_IZQUIERDA, DIR_DERECHA
direccion_dx: .word  0,  0, -1,  1
direccion_dy: .word -1,  1,  0,  0

# ---- Sprite del tanque descrito con tablas (16 bytes por direccion) ----
# canon_sprite: dx, dy, ancho, alto
canon_sprite:
    .word 2, 0, 1, 3              # arriba
    .word 2, 2, 1, 3              # abajo
    .word 0, 2, 3, 1              # izquierda
    .word 2, 2, 3, 1              # derecha

# orugas_sprite: dx1, dy1, dx2, dy2, ancho, alto  (24 bytes por direccion)
orugas_sprite:
    .word 0, 0, 4, 0, 1, 5        # arriba:     dos barras verticales
    .word 0, 0, 4, 0, 1, 5        # abajo:      dos barras verticales
    .word 0, 0, 0, 4, 5, 1        # izquierda:  dos barras horizontales
    .word 0, 0, 0, 4, 5, 1        # derecha:    dos barras horizontales

# ---- Nivel 1: cada fila es x, y, color, ancho, alto ----
nivel_1_bloques:
    # Parte superior: seis columnas de ladrillo
    .word 5,  5, COLOR_LADRILLO, 5, 22
    .word 15, 5, COLOR_LADRILLO, 5, 22
    .word 25, 5, COLOR_LADRILLO, 5, 17
    .word 35, 5, COLOR_LADRILLO, 5, 17
    .word 45, 5, COLOR_LADRILLO, 5, 22
    .word 55, 5, COLOR_LADRILLO, 5, 22

    # Acero central superior
    .word 30, 15, COLOR_ACERO, 5, 5

    # Dos bloques pequenos bajo las columnas centrales
    .word 25, 27, COLOR_LADRILLO, 5, 5
    .word 35, 27, COLOR_LADRILLO, 5, 5

    # Franja horizontal central
    .word 0,  32, COLOR_ACERO, 5, 5
    .word 10, 32, COLOR_LADRILLO, 10, 5
    .word 44, 32, COLOR_LADRILLO, 10, 5
    .word 59, 32, COLOR_ACERO, 5, 5

    # Obstaculo central con forma de U
    .word 25, 37, COLOR_LADRILLO, 5, 5
    .word 35, 37, COLOR_LADRILLO, 5, 5
    .word 30, 39, COLOR_LADRILLO, 5, 3

    # Parte inferior
    .word 5,  42, COLOR_LADRILLO, 5, 17
    .word 15, 42, COLOR_LADRILLO, 5, 17
    .word 25, 42, COLOR_LADRILLO, 5, 10
    .word 35, 42, COLOR_LADRILLO, 5, 10
    .word 45, 42, COLOR_LADRILLO, 5, 17
    .word 55, 42, COLOR_LADRILLO, 5, 17

    # Proteccion de ladrillo alrededor de la base
    .word 27, 56, COLOR_LADRILLO, 10, 2
    .word 27, 58, COLOR_LADRILLO, 3, 6
    .word 34, 58, COLOR_LADRILLO, 3, 6

    # Cuerpo de la base
    .word BASE_X, BASE_Y, COLOR_BASE, BASE_ANCHO, BASE_ALTO
nivel_1_bloques_fin:

# ---- Pixeles blancos del emblema de la base: pares x, y ----
emblema_base:
    .word 30, 59
    .word 33, 59
    .word 31, 60
    .word 32, 60
    .word 31, 61
    .word 32, 61
emblema_base_fin:


# ================================================================
# 3. PROGRAMA PRINCIPAL
# ================================================================
.text
.globl main

main:
    jal construir_escenario       # el modelo del nivel queda en mapa_terreno
    jal preparar_frame            # copia inicial del escenario al buffer
    jal presentar_frame           # primera imagen completa, una sola vez

bucle_principal:
    jal procesar_entrada          # 1. el jugador manda
    jal actualizar_enemigo        # 2. la IA del enemigo decide
    jal actualizar_balas          # 3. avanzan los proyectiles
    jal dibujar_escena            # 4. se redibuja todo el cuadro
    jal esperar_cuadro            # 5. se respeta el ritmo del juego

    lw t0, partida_terminada
    beqz t0, bucle_principal

    li a7, 10                     # exit
    ecall

# Pausa de un cuadro para que el juego no corra a la velocidad del CPU.
esperar_cuadro:
    li a0, CUADRO_MS
    li a7, 32                     # sleep
    ecall
    ret


# ================================================================
# 4. ENTRADA DEL JUGADOR
# ================================================================

# El MMIO de RARS no informa cuando se libera una tecla. Por eso el jugador
# avanza solamente cuando llega un evento real: al mantener W/A/S/D, el
# auto-repeat del sistema genera esos eventos; al soltarla, deja de avanzar.
procesar_entrada:
    addi sp, sp, -12
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)

    li t0, KEY_STATUS_ADDRESS
    lw t1, 0(t0)
    andi t1, t1, 1                # bit 0 = hay una tecla lista
    beqz t1, procesar_entrada_fin

    li t0, KEY_INPUT_ADDRESS
    lw t1, 0(t0)                  # leer la tecla tambien la consume

    li t2, ASCII_ESPACIO
    beq t1, t2, procesar_entrada_disparo

    # Traducir la tecla en una direccion; cualquier otra tecla se ignora.
    li t2, ASCII_W
    beq t1, t2, procesar_entrada_arriba
    li t2, ASCII_S
    beq t1, t2, procesar_entrada_abajo
    li t2, ASCII_A
    beq t1, t2, procesar_entrada_izquierda
    li t2, ASCII_D
    beq t1, t2, procesar_entrada_derecha
    j procesar_entrada_fin

procesar_entrada_arriba:
    li a1, DIR_ARRIBA
    j procesar_entrada_mover
procesar_entrada_abajo:
    li a1, DIR_ABAJO
    j procesar_entrada_mover
procesar_entrada_izquierda:
    li a1, DIR_IZQUIERDA
    j procesar_entrada_mover
procesar_entrada_derecha:
    li a1, DIR_DERECHA

procesar_entrada_mover:
    mv s0, a1
    li s1, JUGADOR_PASOS_POR_EVENTO
procesar_entrada_mover_paso:
    la a0, tanque_jugador
    mv a1, s0
    jal mover_tanque
    beqz a0, procesar_entrada_fin
    addi s1, s1, -1
    bnez s1, procesar_entrada_mover_paso
    j procesar_entrada_fin

procesar_entrada_disparo:
    la a0, tanque_jugador
    la a1, bala_jugador
    jal disparar

procesar_entrada_fin:
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 12
    ret


# ================================================================
# 5. TANQUES: MOVIMIENTO, DISPARO E IA DEL ENEMIGO
# ================================================================

# mover_tanque
#   a0 = puntero al tanque
#   a1 = direccion deseada
#   a0 = 1 si avanzo un pixel, 0 si quedo bloqueado
# El tanque siempre gira hacia la direccion pedida, aunque no avance.
mover_tanque:
    addi sp, sp, -16
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)

    mv s0, a0
    sw a1, T_DIR(s0)

    mv a0, a1
    jal delta_direccion           # a0 = dx, a1 = dy

    lw s1, T_X(s0)
    add s1, s1, a0                # x de destino
    lw s2, T_Y(s0)
    add s2, s2, a1                # y de destino

    # El destino debe caber en pantalla y estar sobre terreno libre.
    mv a0, s1
    mv a1, s2
    li a2, TANQUE_TAM
    li a3, TANQUE_TAM
    jal hay_colision_terreno
    bnez a0, mover_tanque_bloqueado

    # Tampoco puede encimarse con el otro tanque.
    mv a0, s0
    jal tanque_contrario
    mv a1, s1
    mv a2, s2
    jal choca_con_tanque
    bnez a0, mover_tanque_bloqueado

    sw s1, T_X(s0)
    sw s2, T_Y(s0)
    li a0, 1
    j mover_tanque_fin

mover_tanque_bloqueado:
    li a0, 0

mover_tanque_fin:
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# disparar
#   a0 = puntero al tanque que dispara
#   a1 = puntero a su bala
# La bala nace justo delante del canon: centro del tanque + 3 * direccion.
disparar:
    addi sp, sp, -12
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)

    mv s0, a0
    mv s1, a1

    lw t0, T_VIVO(s0)
    beqz t0, disparar_fin
    lw t0, B_ACTIVA(s1)
    bnez t0, disparar_fin         # solo un proyectil propio a la vez

    lw a0, T_DIR(s0)
    sw a0, B_DIR(s1)
    jal delta_direccion           # a0 = dx, a1 = dy

    slli t0, a0, 1                # dx * 3 = dx*2 + dx
    add t0, t0, a0
    lw t1, T_X(s0)
    addi t1, t1, 2                # centro del tanque
    add t1, t1, t0
    sw t1, B_X(s1)

    slli t0, a1, 1
    add t0, t0, a1
    lw t1, T_Y(s0)
    addi t1, t1, 2
    add t1, t1, t0
    sw t1, B_Y(s1)

    li t0, 1
    sw t0, B_ACTIVA(s1)

    # Resolver ya el pixel de salida: asi funcionan los tiros a quemarropa.
    mv a0, s1
    jal resolver_impacto

disparar_fin:
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 12
    ret

# actualizar_enemigo
# IA del primer enemigo, con dos relojes independientes:
#   - uno decide cuando avanzar un pixel,
#   - otro decide cuando disparar.
# Si choca contra algo (o de vez en cuando) elige un rumbo al azar.
actualizar_enemigo:
    addi sp, sp, -8
    sw ra, 0(sp)
    sw s0, 4(sp)

    la s0, tanque_enemigo
    lw t0, T_VIVO(s0)
    beqz t0, actualizar_enemigo_fin

    # --- Reloj de disparo ---
    lw t0, T_RETARDO_DISPARO(s0)
    addi t0, t0, -1
    sw t0, T_RETARDO_DISPARO(s0)
    bgtz t0, actualizar_enemigo_mover

    lw t0, T_PERIODO_DISPARO(s0)
    sw t0, T_RETARDO_DISPARO(s0)
    mv a0, s0
    la a1, bala_enemigo
    jal disparar

    # --- Reloj de movimiento ---
actualizar_enemigo_mover:
    lw t0, T_RETARDO_MOV(s0)
    addi t0, t0, -1
    sw t0, T_RETARDO_MOV(s0)
    bgtz t0, actualizar_enemigo_fin

    lw t0, T_PERIODO_MOV(s0)
    sw t0, T_RETARDO_MOV(s0)

    mv a0, s0
    lw a1, T_DIR(s0)
    jal mover_tanque
    beqz a0, actualizar_enemigo_girar   # bloqueado: hay que buscar otra ruta

    # Aunque avance, a veces cambia de rumbo para no ser predecible.
    li a0, ENEMIGO_PROB_GIRO
    jal numero_aleatorio
    bnez a0, actualizar_enemigo_fin

actualizar_enemigo_girar:
    li a0, 4
    jal numero_aleatorio          # a0 = 0..3, una de las cuatro direcciones
    sw a0, T_DIR(s0)

actualizar_enemigo_fin:
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 8
    ret

# tanque_contrario
#   a0 = puntero a un tanque -> a0 = puntero al tanque rival
tanque_contrario:
    la t0, tanque_jugador
    la t1, tanque_enemigo
    beq a0, t0, tanque_contrario_enemigo
    mv a0, t0
    ret
tanque_contrario_enemigo:
    mv a0, t1
    ret

# destruir_tanque
#   a0 = puntero al tanque alcanzado
# El enemigo desaparece. El jugador reaparece en su posicion inicial.
# Ninguno de los dos casos modifica permanentemente el terreno.
destruir_tanque:
    la t0, tanque_jugador
    bne a0, t0, destruir_tanque_enemigo

    li t1, JUGADOR_X_INICIAL
    sw t1, T_X(a0)
    li t1, JUGADOR_Y_INICIAL
    sw t1, T_Y(a0)
    li t1, DIR_ARRIBA
    sw t1, T_DIR(a0)
    li t1, 1
    sw t1, T_VIVO(a0)
    ret

destruir_tanque_enemigo:
    sw zero, T_VIVO(a0)
    ret


# ================================================================
# 6. BALAS
# ================================================================

actualizar_balas:
    addi sp, sp, -4
    sw ra, 0(sp)

    la a0, bala_jugador
    jal actualizar_bala
    la a0, bala_enemigo
    jal actualizar_bala

    lw ra, 0(sp)
    addi sp, sp, 4
    ret

# actualizar_bala
#   a0 = puntero a la bala
# Avanza pixel a pixel (no de golpe) para no saltarse ningun obstaculo.
actualizar_bala:
    addi sp, sp, -12
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)

    mv s0, a0
    li s1, BALA_PASOS_POR_CUADRO

actualizar_bala_paso:
    beqz s1, actualizar_bala_fin
    lw t0, B_ACTIVA(s0)
    beqz t0, actualizar_bala_fin

    lw a0, B_DIR(s0)
    jal delta_direccion           # a0 = dx, a1 = dy

    lw t0, B_X(s0)
    add t0, t0, a0
    sw t0, B_X(s0)
    lw t0, B_Y(s0)
    add t0, t0, a1
    sw t0, B_Y(s0)

    mv a0, s0
    jal resolver_impacto

    addi s1, s1, -1
    j actualizar_bala_paso

actualizar_bala_fin:
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 12
    ret

# resolver_impacto
#   a0 = puntero a la bala
# Decide que hay en el pixel que acaba de ocupar la bala:
#   fuera de pantalla / acero -> la bala se apaga
#   base                      -> fin de la partida
#   tanque rival              -> tanque destruido
#   ladrillo                  -> se abre un boquete y la bala se apaga
#   vacio o agua              -> la bala sigue volando
resolver_impacto:
    addi sp, sp, -8
    sw ra, 0(sp)
    sw s0, 4(sp)

    mv s0, a0

    lw t0, B_X(s0)
    lw t1, B_Y(s0)
    bltz t0, resolver_impacto_apagar
    bltz t1, resolver_impacto_apagar
    li t2, SCREEN_WIDTH
    bge t0, t2, resolver_impacto_apagar
    li t2, SCREEN_HEIGHT
    bge t1, t2, resolver_impacto_apagar

    mv a0, t0
    mv a1, t1
    jal es_base
    bnez a0, resolver_impacto_base

    mv a0, s0
    jal tanque_alcanzado          # a0 = tanque rival tocado, o 0
    bnez a0, resolver_impacto_tanque

    lw a0, B_X(s0)
    lw a1, B_Y(s0)
    jal leer_terreno              # a0 = color del pixel del escenario

    beqz a0, resolver_impacto_fin           # vacio: sigue volando
    li t0, COLOR_AGUA
    beq a0, t0, resolver_impacto_fin        # el agua no frena al proyectil
    li t0, COLOR_LADRILLO
    beq a0, t0, resolver_impacto_ladrillo
    j resolver_impacto_apagar               # acero u otro material duro

resolver_impacto_ladrillo:
    mv a0, s0
    jal destruir_ladrillos
    j resolver_impacto_apagar

resolver_impacto_tanque:
    jal destruir_tanque
    j resolver_impacto_apagar

resolver_impacto_base:
    li a0, BASE_X
    li a1, BASE_Y
    li a2, COLOR_ROJO
    li a3, BASE_ANCHO
    li a4, BASE_ALTO
    la a5, mapa_terreno
    jal rellenar_rect

    li a0, BASE_X
    li a1, BASE_Y
    li a2, COLOR_ROJO
    li a3, BASE_ANCHO
    li a4, BASE_ALTO
    la a5, buffer_frame
    jal rellenar_rect

    li a0, BASE_X
    li a1, BASE_Y
    li a2, COLOR_ROJO
    li a3, BASE_ANCHO
    li a4, BASE_ALTO
    mv a5, gp
    jal rellenar_rect

    la a0, mensaje_base
    jal terminar_partida

resolver_impacto_apagar:
    sw zero, B_ACTIVA(s0)

resolver_impacto_fin:
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 8
    ret

# tanque_alcanzado
#   a0 = puntero a la bala
#   a0 = puntero al tanque rival tocado, o 0 si no toco a nadie
# Una bala solo danna al bando contrario, nunca a quien la disparo.
tanque_alcanzado:
    lw t0, B_DUENO(a0)
    la t1, tanque_enemigo         # objetivo por defecto: bala del jugador
    beqz t0, tanque_alcanzado_comprobar
    la t1, tanque_jugador

tanque_alcanzado_comprobar:
    lw t2, T_VIVO(t1)
    beqz t2, tanque_alcanzado_no

    lw t2, B_X(a0)
    lw t3, B_Y(a0)
    lw t4, T_X(t1)
    lw t5, T_Y(t1)

    blt t2, t4, tanque_alcanzado_no
    addi t6, t4, TANQUE_TAM
    bge t2, t6, tanque_alcanzado_no
    blt t3, t5, tanque_alcanzado_no
    addi t6, t5, TANQUE_TAM
    bge t3, t6, tanque_alcanzado_no

    mv a0, t1
    ret

tanque_alcanzado_no:
    li a0, 0
    ret


# ================================================================
# 7. COLISIONES Y DESTRUCCION DEL ESCENARIO
# ================================================================

# hay_colision_terreno
#   a0 = x, a1 = y, a2 = ancho, a3 = alto
#   a0 = 1 si el rectangulo se sale de pantalla o pisa terreno ocupado
# En el modelo, todo pixel distinto de negro es un obstaculo solido.
hay_colision_terreno:
    bltz a0, hay_colision_terreno_si
    bltz a1, hay_colision_terreno_si
    add t0, a0, a2
    li t1, SCREEN_WIDTH
    bgt t0, t1, hay_colision_terreno_si
    add t0, a1, a3
    li t1, SCREEN_HEIGHT
    bgt t0, t1, hay_colision_terreno_si

    mv t0, a1                     # fila actual
    add t1, a1, a3                # primera fila fuera del rectangulo
hay_colision_terreno_fila:
    bge t0, t1, hay_colision_terreno_no
    mv t2, a0                     # columna actual
    add t3, a0, a2
hay_colision_terreno_columna:
    bge t2, t3, hay_colision_terreno_siguiente
    slli t4, t0, 6                # (y * 64 + x) * 4
    add t4, t4, t2
    slli t4, t4, 2
    la t5, mapa_terreno
    add t5, t5, t4
    lw t6, 0(t5)
    bnez t6, hay_colision_terreno_si
    addi t2, t2, 1
    j hay_colision_terreno_columna
hay_colision_terreno_siguiente:
    addi t0, t0, 1
    j hay_colision_terreno_fila

hay_colision_terreno_no:
    li a0, 0
    ret
hay_colision_terreno_si:
    li a0, 1
    ret

# choca_con_tanque
#   a0 = puntero al otro tanque, a1 = x, a2 = y del rectangulo 5x5
#   a0 = 1 si los dos cuadrados de 5x5 se solapan
choca_con_tanque:
    lw t0, T_VIVO(a0)
    beqz t0, choca_con_tanque_no

    lw t0, T_X(a0)
    lw t1, T_Y(a0)

    addi t2, t0, TANQUE_TAM
    bge a1, t2, choca_con_tanque_no     # el nuevo esta a la derecha
    addi t2, a1, TANQUE_TAM
    bge t0, t2, choca_con_tanque_no     # el nuevo esta a la izquierda
    addi t2, t1, TANQUE_TAM
    bge a2, t2, choca_con_tanque_no     # el nuevo esta debajo
    addi t2, a2, TANQUE_TAM
    bge t1, t2, choca_con_tanque_no     # el nuevo esta encima

    li a0, 1
    ret
choca_con_tanque_no:
    li a0, 0
    ret

# es_base
#   a0 = x, a1 = y -> a0 = 1 si el pixel pertenece al aguila
es_base:
    li t0, BASE_X
    blt a0, t0, es_base_no
    addi t1, t0, BASE_ANCHO
    bge a0, t1, es_base_no
    li t0, BASE_Y
    blt a1, t0, es_base_no
    addi t1, t0, BASE_ALTO
    bge a1, t1, es_base_no
    li a0, 1
    ret
es_base_no:
    li a0, 0
    ret

# destruir_ladrillos
#   a0 = puntero a la bala
# Abre un boquete de 5x2 perpendicular a la trayectoria del disparo.
destruir_ladrillos:
    addi sp, sp, -4
    sw ra, 0(sp)

    lw t0, B_X(a0)
    lw t1, B_Y(a0)
    lw t2, B_DIR(a0)

    li t3, DIR_IZQUIERDA
    bge t2, t3, destruir_ladrillos_horizontal

    # Disparo vertical: boquete ancho (5) y poco profundo (2).
    addi a0, t0, -2
    mv a1, t1
    li t3, DIR_ARRIBA
    bne t2, t3, destruir_ladrillos_vertical_listo
    addi a1, a1, -1               # hacia arriba el boquete crece al reves
destruir_ladrillos_vertical_listo:
    li a2, 5                      # ancho
    li a3, 2                      # alto
    j destruir_ladrillos_aplicar

destruir_ladrillos_horizontal:
    # Disparo horizontal: boquete alto (5) y poco profundo (2).
    mv a0, t0
    addi a1, t1, -2
    li t3, DIR_IZQUIERDA
    bne t2, t3, destruir_ladrillos_horizontal_listo
    addi a0, a0, -1
destruir_ladrillos_horizontal_listo:
    li a2, 2                      # ancho
    li a3, 5                      # alto

destruir_ladrillos_aplicar:
    jal borrar_ladrillos_rect

    lw ra, 0(sp)
    addi sp, sp, 4
    ret

# borrar_ladrillos_rect
#   a0 = x, a1 = y, a2 = ancho, a3 = alto
# Pone a negro solo los pixeles de ladrillo: el acero y la base aguantan.
borrar_ladrillos_rect:
    mv t0, a1
    add t1, a1, a3
borrar_ladrillos_rect_fila:
    bge t0, t1, borrar_ladrillos_rect_fin
    mv t2, a0
    add t3, a0, a2
borrar_ladrillos_rect_columna:
    bge t2, t3, borrar_ladrillos_rect_siguiente
    bltz t2, borrar_ladrillos_rect_avanzar
    bltz t0, borrar_ladrillos_rect_avanzar
    li t4, SCREEN_WIDTH
    bge t2, t4, borrar_ladrillos_rect_avanzar
    li t4, SCREEN_HEIGHT
    bge t0, t4, borrar_ladrillos_rect_avanzar

    slli t4, t0, 6
    add t4, t4, t2
    slli t4, t4, 2
    la t5, mapa_terreno
    add t5, t5, t4
    lw t6, 0(t5)
    li t4, COLOR_LADRILLO
    bne t6, t4, borrar_ladrillos_rect_avanzar
    sw zero, 0(t5)

    # Mantener sincronizados el cuadro oculto y la pantalla visible.
    slli t4, t0, 6
    add t4, t4, t2
    slli t4, t4, 2
    la t5, buffer_frame
    add t5, t5, t4
    sw zero, 0(t5)
    add t5, gp, t4
    sw zero, 0(t5)

borrar_ladrillos_rect_avanzar:
    addi t2, t2, 1
    j borrar_ladrillos_rect_columna
borrar_ladrillos_rect_siguiente:
    addi t0, t0, 1
    j borrar_ladrillos_rect_fila
borrar_ladrillos_rect_fin:
    ret

# terminar_partida
#   a0 = puntero al mensaje que se imprime en consola
terminar_partida:
    li a7, 4                      # print string
    ecall
    li t0, 1
    la t1, partida_terminada
    sw t0, 0(t1)
    ret


# ================================================================
# 8. DIBUJO (VISTA)
# ================================================================

# construir_escenario
# Convierte la tabla del nivel en el modelo mapa_terreno.
construir_escenario:
    addi sp, sp, -12
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)

    jal limpiar_terreno

    la s0, nivel_1_bloques
    la s1, nivel_1_bloques_fin
construir_escenario_bloque:
    bgeu s0, s1, construir_escenario_emblema
    lw a0, 0(s0)                  # x
    lw a1, 4(s0)                  # y
    lw a2, 8(s0)                  # color
    lw a3, 12(s0)                 # ancho
    lw a4, 16(s0)                 # alto
    la a5, mapa_terreno
    jal rellenar_rect
    addi s0, s0, BLOQUE_TAM
    j construir_escenario_bloque

construir_escenario_emblema:
    la s0, emblema_base
    la s1, emblema_base_fin
construir_escenario_pixel:
    bgeu s0, s1, construir_escenario_fin
    lw a0, 0(s0)
    lw a1, 4(s0)
    li a2, COLOR_BLANCO
    la a3, mapa_terreno
    jal escribir_pixel
    addi s0, s0, 8
    j construir_escenario_pixel

construir_escenario_fin:
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 12
    ret

# dibujar_escena
# Aplica doble buffer sin recorrer los 4096 pixeles en cada cuadro:
#   1. restaura en el buffer solo las posiciones anteriores de los sprites,
#   2. dibuja sus posiciones actuales,
#   3. presenta unicamente esos rectangulos pequenos.
dibujar_escena:
    addi sp, sp, -4
    sw ra, 0(sp)

    jal restaurar_sprites_anteriores

    la a0, tanque_jugador
    jal dibujar_tanque
    la a0, tanque_enemigo
    jal dibujar_tanque

    la a0, bala_jugador
    jal dibujar_bala
    la a0, bala_enemigo
    jal dibujar_bala

    jal presentar_zonas_sprites
    jal guardar_estado_render

    lw ra, 0(sp)
    addi sp, sp, 4
    ret

# limpiar_terreno: deja todo el escenario en negro.
limpiar_terreno:
    la t0, mapa_terreno
    li t1, TOTAL_PIXELES
limpiar_terreno_loop:
    sw zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, limpiar_terreno_loop
    ret

# preparar_frame: copia el escenario al cuadro oculto.
# Los tanques y las balas se dibujan despues sobre esta misma copia.
preparar_frame:
    la t0, mapa_terreno
    la t1, buffer_frame
    li t2, TOTAL_PIXELES
preparar_frame_loop:
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -1
    bnez t2, preparar_frame_loop
    ret

# presentar_frame: lleva a pantalla el cuadro ya terminado.
# Compara contra gp para escribir unicamente los pixeles que cambiaron.
# Asi el Bitmap Display nunca observa el terreno sin sus sprites encima.
presentar_frame:
    la t0, buffer_frame
    mv t1, gp
    li t2, TOTAL_PIXELES
presentar_frame_loop:
    lw t3, 0(t0)                  # color definitivo del cuadro
    lw t4, 0(t1)                  # color que ya se muestra
    beq t3, t4, presentar_frame_siguiente
    sw t3, 0(t1)
presentar_frame_siguiente:
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -1
    bnez t2, presentar_frame_loop
    ret

# restaurar_sprites_anteriores
# Copia del terreno al buffer solo donde habia sprites en el cuadro anterior.
restaurar_sprites_anteriores:
    addi sp, sp, -4
    sw ra, 0(sp)

    la t0, render_jugador
    lw t1, 8(t0)
    beqz t1, restaurar_sprite_enemigo
    lw a0, 0(t0)
    lw a1, 4(t0)
    li a2, TANQUE_TAM
    li a3, TANQUE_TAM
    jal copiar_terreno_a_buffer_rect

restaurar_sprite_enemigo:
    la t0, render_enemigo
    lw t1, 8(t0)
    beqz t1, restaurar_sprite_bala_jugador
    lw a0, 0(t0)
    lw a1, 4(t0)
    li a2, TANQUE_TAM
    li a3, TANQUE_TAM
    jal copiar_terreno_a_buffer_rect

restaurar_sprite_bala_jugador:
    la t0, render_bala_jugador
    lw t1, 8(t0)
    beqz t1, restaurar_sprite_bala_enemigo
    lw a0, 0(t0)
    lw a1, 4(t0)
    li a2, 1
    li a3, 1
    jal copiar_terreno_a_buffer_rect

restaurar_sprite_bala_enemigo:
    la t0, render_bala_enemigo
    lw t1, 8(t0)
    beqz t1, restaurar_sprites_fin
    lw a0, 0(t0)
    lw a1, 4(t0)
    li a2, 1
    li a3, 1
    jal copiar_terreno_a_buffer_rect

restaurar_sprites_fin:
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

# copiar_terreno_a_buffer_rect
#   a0 = x, a1 = y, a2 = ancho, a3 = alto
# Copia un rectangulo pequeno de mapa_terreno a buffer_frame.
copiar_terreno_a_buffer_rect:
    mv t0, a1
    add t1, a1, a3
copiar_terreno_a_buffer_fila:
    bge t0, t1, copiar_terreno_a_buffer_fin
    mv t2, a0
    add t3, a0, a2
copiar_terreno_a_buffer_columna:
    bge t2, t3, copiar_terreno_a_buffer_siguiente
    slli t4, t0, 6
    add t4, t4, t2
    slli t4, t4, 2
    la t5, mapa_terreno
    add t5, t5, t4
    lw t6, 0(t5)
    la t5, buffer_frame
    add t5, t5, t4
    sw t6, 0(t5)
    addi t2, t2, 1
    j copiar_terreno_a_buffer_columna
copiar_terreno_a_buffer_siguiente:
    addi t0, t0, 1
    j copiar_terreno_a_buffer_fila
copiar_terreno_a_buffer_fin:
    ret

# presentar_zonas_sprites
# Presenta las posiciones anteriores (para borrarlas) y las actuales
# (para mostrar el movimiento). presentar_rect omite pixeles sin cambios.
presentar_zonas_sprites:
    addi sp, sp, -4
    sw ra, 0(sp)

    la t0, render_jugador
    lw t1, 8(t0)
    beqz t1, presentar_anterior_enemigo
    lw a0, 0(t0)
    lw a1, 4(t0)
    li a2, TANQUE_TAM
    li a3, TANQUE_TAM
    jal presentar_rect

presentar_anterior_enemigo:
    la t0, render_enemigo
    lw t1, 8(t0)
    beqz t1, presentar_anterior_bala_jugador
    lw a0, 0(t0)
    lw a1, 4(t0)
    li a2, TANQUE_TAM
    li a3, TANQUE_TAM
    jal presentar_rect

presentar_anterior_bala_jugador:
    la t0, render_bala_jugador
    lw t1, 8(t0)
    beqz t1, presentar_anterior_bala_enemigo
    lw a0, 0(t0)
    lw a1, 4(t0)
    li a2, 1
    li a3, 1
    jal presentar_rect

presentar_anterior_bala_enemigo:
    la t0, render_bala_enemigo
    lw t1, 8(t0)
    beqz t1, presentar_actual_jugador
    lw a0, 0(t0)
    lw a1, 4(t0)
    li a2, 1
    li a3, 1
    jal presentar_rect

presentar_actual_jugador:
    la t0, tanque_jugador
    lw t1, T_VIVO(t0)
    beqz t1, presentar_actual_enemigo
    lw a0, T_X(t0)
    lw a1, T_Y(t0)
    li a2, TANQUE_TAM
    li a3, TANQUE_TAM
    jal presentar_rect

presentar_actual_enemigo:
    la t0, tanque_enemigo
    lw t1, T_VIVO(t0)
    beqz t1, presentar_actual_bala_jugador
    lw a0, T_X(t0)
    lw a1, T_Y(t0)
    li a2, TANQUE_TAM
    li a3, TANQUE_TAM
    jal presentar_rect

presentar_actual_bala_jugador:
    la t0, bala_jugador
    lw t1, B_ACTIVA(t0)
    beqz t1, presentar_actual_bala_enemigo
    lw a0, B_X(t0)
    lw a1, B_Y(t0)
    li a2, 1
    li a3, 1
    jal presentar_rect

presentar_actual_bala_enemigo:
    la t0, bala_enemigo
    lw t1, B_ACTIVA(t0)
    beqz t1, presentar_zonas_fin
    lw a0, B_X(t0)
    lw a1, B_Y(t0)
    li a2, 1
    li a3, 1
    jal presentar_rect

presentar_zonas_fin:
    lw ra, 0(sp)
    addi sp, sp, 4
    ret

# presentar_rect
#   a0 = x, a1 = y, a2 = ancho, a3 = alto
# Copia del buffer a gp solo los pixeles diferentes.
presentar_rect:
    mv t0, a1
    add t1, a1, a3
presentar_rect_fila:
    bge t0, t1, presentar_rect_fin
    mv t2, a0
    add t3, a0, a2
presentar_rect_columna:
    bge t2, t3, presentar_rect_siguiente
    slli t4, t0, 6
    add t4, t4, t2
    slli t4, t4, 2
    la t5, buffer_frame
    add t5, t5, t4
    lw t6, 0(t5)
    add t5, gp, t4
    lw t4, 0(t5)
    beq t6, t4, presentar_rect_avanzar
    sw t6, 0(t5)
presentar_rect_avanzar:
    addi t2, t2, 1
    j presentar_rect_columna
presentar_rect_siguiente:
    addi t0, t0, 1
    j presentar_rect_fila
presentar_rect_fin:
    ret

# guardar_estado_render
# Guarda las posiciones que habra que restaurar en el siguiente cuadro.
guardar_estado_render:
    la t0, tanque_jugador
    la t1, render_jugador
    lw t2, T_X(t0)
    sw t2, 0(t1)
    lw t2, T_Y(t0)
    sw t2, 4(t1)
    lw t2, T_VIVO(t0)
    sw t2, 8(t1)

    la t0, tanque_enemigo
    la t1, render_enemigo
    lw t2, T_X(t0)
    sw t2, 0(t1)
    lw t2, T_Y(t0)
    sw t2, 4(t1)
    lw t2, T_VIVO(t0)
    sw t2, 8(t1)

    la t0, bala_jugador
    la t1, render_bala_jugador
    lw t2, B_X(t0)
    sw t2, 0(t1)
    lw t2, B_Y(t0)
    sw t2, 4(t1)
    lw t2, B_ACTIVA(t0)
    sw t2, 8(t1)

    la t0, bala_enemigo
    la t1, render_bala_enemigo
    lw t2, B_X(t0)
    sw t2, 0(t1)
    lw t2, B_Y(t0)
    sw t2, 4(t1)
    lw t2, B_ACTIVA(t0)
    sw t2, 8(t1)
    ret

# dibujar_tanque
#   a0 = puntero al tanque
# El sprite de 5x5 se arma con tres piezas leidas de las tablas:
#   dos orugas, el casco central de 3x3 y el canon.
dibujar_tanque:
    addi sp, sp, -16
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)

    mv s0, a0
    lw t0, T_VIVO(s0)
    beqz t0, dibujar_tanque_fin

    lw s1, T_DIR(s0)

    # --- Orugas: fila de 6 palabras = 24 bytes por direccion ---
    slli t0, s1, 4                # dir * 24 = dir * 16 + dir * 8
    slli t1, s1, 3
    add t0, t0, t1
    la s2, orugas_sprite
    add s2, s2, t0

    lw t0, 0(s2)                  # dx de la primera oruga
    lw t1, 4(s2)                  # dy de la primera oruga
    lw a0, T_X(s0)
    add a0, a0, t0
    lw a1, T_Y(s0)
    add a1, a1, t1
    li a2, COLOR_ORUGA
    lw a3, 16(s2)
    lw a4, 20(s2)
    la a5, buffer_frame
    jal rellenar_rect

    lw t0, 8(s2)                  # dx de la segunda oruga
    lw t1, 12(s2)                 # dy de la segunda oruga
    lw a0, T_X(s0)
    add a0, a0, t0
    lw a1, T_Y(s0)
    add a1, a1, t1
    li a2, COLOR_ORUGA
    lw a3, 16(s2)
    lw a4, 20(s2)
    la a5, buffer_frame
    jal rellenar_rect

    # --- Casco: cuadrado de 3x3 centrado ---
    lw a0, T_X(s0)
    addi a0, a0, 1
    lw a1, T_Y(s0)
    addi a1, a1, 1
    lw a2, T_COLOR_CUERPO(s0)
    li a3, 3
    li a4, 3
    la a5, buffer_frame
    jal rellenar_rect

    # --- Canon: fila de 4 palabras = 16 bytes por direccion ---
    slli t0, s1, 4
    la s2, canon_sprite
    add s2, s2, t0

    lw t0, 0(s2)
    lw t1, 4(s2)
    lw a0, T_X(s0)
    add a0, a0, t0
    lw a1, T_Y(s0)
    add a1, a1, t1
    lw a2, T_COLOR_CANON(s0)
    lw a3, 8(s2)
    lw a4, 12(s2)
    la a5, buffer_frame
    jal rellenar_rect

dibujar_tanque_fin:
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# dibujar_bala
#   a0 = puntero a la bala (un unico pixel blanco)
dibujar_bala:
    addi sp, sp, -4
    sw ra, 0(sp)

    lw t0, B_ACTIVA(a0)
    beqz t0, dibujar_bala_fin

    lw t1, B_X(a0)
    lw t2, B_Y(a0)
    mv a0, t1
    mv a1, t2
    li a2, COLOR_BLANCO
    la a3, buffer_frame
    jal escribir_pixel

dibujar_bala_fin:
    lw ra, 0(sp)
    addi sp, sp, 4
    ret


# ================================================================
# 9. PRIMITIVAS DE DIBUJO
# El mismo codigo pinta sobre lienzos de 64x64 palabras:
#   mapa_terreno -> el modelo persistente del escenario
#   buffer_frame -> el cuadro oculto que se esta construyendo
#   gp           -> la pantalla visible
# ================================================================

# escribir_pixel
#   a0 = x, a1 = y, a2 = color, a3 = direccion base del lienzo
#   Posicion = base + (y * 64 + x) * 4
escribir_pixel:
    slli t0, a1, 6
    add t0, t0, a0
    slli t0, t0, 2
    add t0, a3, t0
    sw a2, 0(t0)
    ret

# leer_terreno
#   a0 = x, a1 = y -> a0 = color del escenario en ese pixel
leer_terreno:
    slli t0, a1, 6
    add t0, t0, a0
    slli t0, t0, 2
    la t1, mapa_terreno
    add t1, t1, t0
    lw a0, 0(t1)
    ret

# rellenar_rect
#   a0 = x, a1 = y, a2 = color, a3 = ancho, a4 = alto
#   a5 = direccion base del lienzo
# Dos bucles anidados: filas por fuera, columnas por dentro.
rellenar_rect:
    mv t0, a1                     # fila actual
    add t1, a1, a4                # primera fila fuera del rectangulo
rellenar_rect_fila:
    bge t0, t1, rellenar_rect_fin
    mv t2, a0                     # columna actual
    add t3, a0, a3
rellenar_rect_columna:
    bge t2, t3, rellenar_rect_siguiente
    slli t4, t0, 6
    add t4, t4, t2
    slli t4, t4, 2
    add t4, a5, t4
    sw a2, 0(t4)
    addi t2, t2, 1
    j rellenar_rect_columna
rellenar_rect_siguiente:
    addi t0, t0, 1
    j rellenar_rect_fila
rellenar_rect_fin:
    ret


# ================================================================
# 10. UTILIDADES
# ================================================================

# delta_direccion
#   a0 = direccion -> a0 = dx, a1 = dy
# Una consulta a tablas sustituye a cuatro comparaciones encadenadas.
delta_direccion:
    slli t0, a0, 2                # indice * 4 bytes por palabra
    la t1, direccion_dx
    add t1, t1, t0
    la t2, direccion_dy
    add t2, t2, t0
    lw a0, 0(t1)
    lw a1, 0(t2)
    ret

# numero_aleatorio
#   a0 = limite superior -> a0 = valor en el rango 0 .. limite-1
numero_aleatorio:
    mv a1, a0
    li a0, 0                      # generador numero 0
    li a7, 42                     # random int range
    ecall
    ret
