# ================================================================
# Battle City - Nivel 1 adaptado a una pantalla bitmap de 64x64
# Arquitectura: RISC-V (RARS)
#
# Configuracion sugerida del Bitmap Display:
#   Unit Width in Pixels:  8
#   Unit Height in Pixels: 8
#   Display Width:         64
#   Display Height:        64
#   Base address:          gp
#
# Controles:
#   W = arriba
#   S = abajo
#   A = izquierda
#   D = derecha
# ================================================================

.eqv KEY_INPUT_ADDRESS  0xFFFF0004
.eqv KEY_STATUS_ADDRESS 0xFFFF0000

# Caracteres ASCII en minuscula
.eqv ASCII_W 119
.eqv ASCII_S 115
.eqv ASCII_A 97
.eqv ASCII_D 100

# Dimensiones del framebuffer
.eqv SCREEN_WIDTH  64
.eqv SCREEN_HEIGHT 64

# Colores en formato 0x00RRGGBB
.eqv COLOR_BLANCO  0x00FFFFFF
.eqv COLOR_NEGRO   0x00000000
.eqv COLOR_ROJO    0x00FF0000
.eqv COLOR_AZUL    0x000000FF
.eqv COLOR_LADRILLO 0x00E86F00
.eqv COLOR_ACERO   0x00B0B0B0
.eqv COLOR_AGUA    0x000066CC
.eqv COLOR_BASE    0x00FFD000

.data
.align 2

# Posicion inicial del jugador
pixel_x: .word 32
pixel_y: .word 32

# Cada entrada del nivel contiene cinco palabras:
#   x, y, color, ancho, alto
# Cada entrada ocupa 20 bytes.
nivel_1_bloques:
    # Parte superior: seis columnas
    .word 5,  5, COLOR_LADRILLO, 5, 22
    .word 15, 5, COLOR_LADRILLO, 5, 22
    .word 25, 5, COLOR_LADRILLO, 5, 17
    .word 35, 5, COLOR_LADRILLO, 5, 17
    .word 45, 5, COLOR_LADRILLO, 5, 22
    .word 55, 5, COLOR_LADRILLO, 5, 22

    # Acero central superior
    .word 30, 15, COLOR_ACERO, 5, 5

    # Dos bloques pequenos debajo de las columnas centrales
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

    # Proteccion de la base
    .word 27, 56, COLOR_LADRILLO, 10, 2
    .word 27, 58, COLOR_LADRILLO, 3, 6
    .word 34, 58, COLOR_LADRILLO, 3, 6

    # Cuerpo de la base
    .word 30, 58, COLOR_BASE, 4, 5
nivel_1_bloques_fin:

.text
.globl main

# ================================================================
# Programa principal
# ================================================================
main:
    # Limpiar la pantalla antes de pintar el nivel.
    jal limpiar_pantalla
    jal pintar_nivel_1

    # Pintar el jugador en su posicion inicial.
    lw a0, pixel_x
    lw a1, pixel_y
    li a2, COLOR_BLANCO
    jal pintar_pixel

espera_teclado:
    # Consultar el registro de estado del teclado.
    li t0, KEY_STATUS_ADDRESS
    lw t1, 0(t0)
    beqz t1, espera_teclado

    jal mover_pixel

    # Limpiar el estado del teclado.
    li t0, KEY_STATUS_ADDRESS
    sw zero, 0(t0)
    j espera_teclado

# ================================================================
# Funcion: limpiar_pantalla
# Llena los 4096 pixeles del framebuffer con negro.
# ================================================================
limpiar_pantalla:
    mv t0, gp
    li t1, 4096
    li t2, COLOR_NEGRO

limpiar_pantalla_loop:
    sw t2, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, limpiar_pantalla_loop
    ret

# ================================================================
# Funcion: pintar_nivel_1
# Pinta el primer nivel de Battle City mediante una tabla de bloques.
# ================================================================
pintar_nivel_1:
    addi sp, sp, -12
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)

    la s0, nivel_1_bloques
    la s1, nivel_1_bloques_fin

pintar_nivel_1_loop:
    bgeu s0, s1, pintar_nivel_1_detalles

    lw a0, 0(s0)       # x
    lw a1, 4(s0)       # y
    lw a2, 8(s0)       # color
    lw a3, 12(s0)      # ancho
    lw a4, 16(s0)      # alto
    jal pintar_bloque

    addi s0, s0, 20
    j pintar_nivel_1_loop

pintar_nivel_1_detalles:
    # Detalles blancos del emblema de la base.
    li a0, 30
    li a1, 59
    li a2, COLOR_BLANCO
    jal pintar_pixel

    li a0, 33
    li a1, 59
    li a2, COLOR_BLANCO
    jal pintar_pixel

    li a0, 31
    li a1, 60
    li a2, COLOR_BLANCO
    jal pintar_pixel

    li a0, 32
    li a1, 60
    li a2, COLOR_BLANCO
    jal pintar_pixel

    li a0, 31
    li a1, 61
    li a2, COLOR_BLANCO
    jal pintar_pixel

    li a0, 32
    li a1, 61
    li a2, COLOR_BLANCO
    jal pintar_pixel

    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 12
    ret

# ================================================================
# Funcion: mover_pixel
# Lee W, A, S o D y mueve el jugador un pixel si el destino esta libre.
# ================================================================
mover_pixel:
    addi sp, sp, -16
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)

    # s0 y s1 contienen inicialmente la posicion actual.
    lw s0, pixel_x
    lw s1, pixel_y

    li t2, KEY_INPUT_ADDRESS
    lw t0, 0(t2)

    li t1, ASCII_W
    beq t0, t1, mover_arriba

    li t1, ASCII_S
    beq t0, t1, mover_abajo

    li t1, ASCII_A
    beq t0, t1, mover_izquierda

    li t1, ASCII_D
    beq t0, t1, mover_derecha

    # Ignorar cualquier otra tecla.
    j mover_pixel_fin

mover_arriba:
    addi a0, s0, 0
    addi a1, s1, -1
    jal verificar_colision
    bnez a0, mover_pixel_fin
    addi s1, s1, -1
    j actualizar_pixel

mover_abajo:
    addi a0, s0, 0
    addi a1, s1, 1
    jal verificar_colision
    bnez a0, mover_pixel_fin
    addi s1, s1, 1
    j actualizar_pixel

mover_izquierda:
    addi a0, s0, -1
    addi a1, s1, 0
    jal verificar_colision
    bnez a0, mover_pixel_fin
    addi s0, s0, -1
    j actualizar_pixel

mover_derecha:
    addi a0, s0, 1
    addi a1, s1, 0
    jal verificar_colision
    bnez a0, mover_pixel_fin
    addi s0, s0, 1

actualizar_pixel:
    # Borrar la posicion anterior.
    lw a0, pixel_x
    lw a1, pixel_y
    li a2, COLOR_NEGRO
    jal pintar_pixel

    # Pintar la posicion nueva.
    mv a0, s0
    mv a1, s1
    li a2, COLOR_BLANCO
    jal pintar_pixel

    # Guardar la posicion nueva.
    sw s0, pixel_x, t0
    sw s1, pixel_y, t0

mover_pixel_fin:
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# ================================================================
# Funcion: pintar_pixel
# Parametros:
#   a0 = coordenada x
#   a1 = coordenada y
#   a2 = color
# ================================================================
pintar_pixel:
    addi sp, sp, -16
    sw ra, 0(sp)
    sw s0, 4(sp)

    mv s0, a2
    jal calcular_posicion_fb
    sw s0, 0(a0)

    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# ================================================================
# Funcion: pintar_bloque
# Parametros:
#   a0 = x de la esquina superior izquierda
#   a1 = y de la esquina superior izquierda
#   a2 = color
#   a3 = ancho en pixeles
#   a4 = alto en pixeles
# ================================================================
pintar_bloque:
    addi sp, sp, -32
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)

    mv s0, a0
    mv s1, a1
    mv s2, a2
    mv s3, a3
    mv s4, a4

pintar_bloque_loop:
    beqz s4, pintar_bloque_fin

    mv a0, s0
    mv a1, s1
    mv a2, s2
    mv a3, s3
    jal pintar_linea_horizontal

    addi s1, s1, 1
    addi s4, s4, -1
    j pintar_bloque_loop

pintar_bloque_fin:
    lw s4, 20(sp)
    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 32
    ret

# ================================================================
# Funcion: pintar_linea_horizontal
# Parametros:
#   a0 = x inicial
#   a1 = y
#   a2 = color
#   a3 = cantidad de pixeles
# ================================================================
pintar_linea_horizontal:
    addi sp, sp, -32
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)

    mv s0, a0
    mv s1, a1
    mv s2, a2
    mv s3, a3

pintar_linea_horizontal_loop:
    beqz s3, pintar_linea_horizontal_fin

    mv a0, s0
    mv a1, s1
    mv a2, s2
    jal pintar_pixel

    addi s0, s0, 1
    addi s3, s3, -1
    j pintar_linea_horizontal_loop

pintar_linea_horizontal_fin:
    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 32
    ret

# ================================================================
# Funcion: pintar_linea_vertical
# Parametros:
#   a0 = x
#   a1 = y inicial
#   a2 = color
#   a3 = cantidad de pixeles
# ================================================================
pintar_linea_vertical:
    addi sp, sp, -32
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)

    mv s0, a0
    mv s1, a1
    mv s2, a2
    mv s3, a3

pintar_linea_vertical_loop:
    beqz s3, pintar_linea_vertical_fin

    mv a0, s0
    mv a1, s1
    mv a2, s2
    jal pintar_pixel

    addi s1, s1, 1
    addi s3, s3, -1
    j pintar_linea_vertical_loop

pintar_linea_vertical_fin:
    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 32
    ret

# ================================================================
# Funcion: pintar_letra_e
# Parametros:
#   a0 = x
#   a1 = y
#   a2 = color
#   a3 = alto
# Conservada como utilidad del programa original.
# ================================================================
pintar_letra_e:
    addi sp, sp, -32
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)

    mv s0, a0
    mv s1, a1
    mv s2, a2
    mv s3, a3

    mv a0, s0
    mv a1, s1
    mv a2, s2
    mv a3, s3
    jal pintar_linea_vertical

    # Las tres barras horizontales tienen tres pixeles.
    mv a0, s0
    mv a1, s1
    mv a2, s2
    li a3, 3
    jal pintar_linea_horizontal

    srli t0, s3, 1
    mv a0, s0
    add a1, s1, t0
    mv a2, s2
    li a3, 3
    jal pintar_linea_horizontal

    mv a0, s0
    add a1, s1, s3
    addi a1, a1, -1
    mv a2, s2
    li a3, 3
    jal pintar_linea_horizontal

    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 32
    ret

# ================================================================
# Funcion: pintar_letra_a
# Parametros:
#   a0 = x
#   a1 = y
#   a2 = color
#   a3 = alto de las columnas
# Conservada como utilidad del programa original.
# ================================================================
pintar_letra_a:
    addi sp, sp, -32
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)

    mv s0, a0
    mv s1, a1
    mv s2, a2
    mv s3, a3

    addi a0, s0, 1
    addi a1, s1, 1
    mv a2, s2
    mv a3, s3
    jal pintar_linea_vertical

    addi a0, s0, 3
    addi a1, s1, 1
    mv a2, s2
    mv a3, s3
    jal pintar_linea_vertical

    addi a0, s0, 2
    mv a1, s1
    mv a2, s2
    jal pintar_pixel

    addi a0, s0, 1
    addi a1, s1, 3
    mv a2, s2
    li a3, 3
    jal pintar_linea_horizontal

    lw s3, 16(sp)
    lw s2, 12(sp)
    lw s1, 8(sp)
    lw s0, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 32
    ret

# ================================================================
# Funcion: calcular_posicion_fb
# Parametros:
#   a0 = x
#   a1 = y
# Retorno:
#   a0 = direccion del pixel en el framebuffer
# Formula: gp + ((y * 64 + x) * 4)
# ================================================================
calcular_posicion_fb:
    slli t0, a1, 6
    add t0, t0, a0
    slli t0, t0, 2
    add a0, gp, t0
    ret

# ================================================================
# Funcion: verificar_colision
# Parametros:
#   a0 = x destino
#   a1 = y destino
# Retorno:
#   a0 = 0 si el destino esta libre
#   a0 = 1 si existe colision o esta fuera de la pantalla
#
# Todo pixel diferente de negro se considera ocupado.
# ================================================================
verificar_colision:
    addi sp, sp, -16
    sw ra, 0(sp)

    # Limites izquierdo y superior.
    bltz a0, verificar_hay_colision
    bltz a1, verificar_hay_colision

    # Limites derecho e inferior.
    li t0, SCREEN_WIDTH
    bge a0, t0, verificar_hay_colision

    li t0, SCREEN_HEIGHT
    bge a1, t0, verificar_hay_colision

    jal calcular_posicion_fb
    lw t1, 0(a0)
    bnez t1, verificar_hay_colision

verificar_no_hay_colision:
    li a0, 0
    j verificar_colision_fin

verificar_hay_colision:
    li a0, 1

verificar_colision_fin:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
