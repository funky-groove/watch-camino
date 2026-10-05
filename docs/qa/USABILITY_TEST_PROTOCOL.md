# Camino Seguro Watch — Protocolo de evaluación de usabilidad con usuarios

Fecha: 2026-10-05 · Ámbito: app watchOS V1 (`docs/WATCH_V1_SPEC.md`) · Marco: ISO 9241-11:2018
(usabilidad = **eficacia**, **eficiencia** y **satisfacción** en un contexto de uso especificado) e
ISO 9241-210 (diseño centrado en el usuario). Requisitos de accesibilidad de referencia:
`docs/accessibility/STANDARDS_MATRIX.md`.

> **ESTADO: PENDIENTE.** La evaluación con personas **no se ha realizado**. Este documento es el
> protocolo a seguir. Ningún resultado de este documento debe citarse como evidencia hasta que se
> rellenen las plantillas de la §9 con sesiones reales. Las capturas automáticas
> (`watchos/scripts/screenshots.sh`) sirven para revisión experta, **no** sustituyen esta prueba.

## 1. Objetivos

1. Comprobar que un peregrino entiende, al levantar la muñeca, cuánto lleva recorrido y cuánto tiempo.
2. Comprobar que encuentra agua cercana y entiende un aviso de punto de interés (POI).
3. Comprobar que sabe si sus datos están guardados / sincronizados.
4. Comprobar que puede cambiar el tema (Negro / Perla) sin ayuda.
5. Detectar barreras para personas mayores, con baja visión (VoiceOver, texto ampliado),
   temblor o daltonismo.

## 2. Contexto de uso

| Aspecto | Contexto previsto | Cómo se reproduce en la prueba |
|---|---|---|
| Usuario | Peregrino a pie, a menudo cansado, con mochila y bastones | Sesión de pie; parte con mochila ligera y un bastón en la mano dominante |
| Entorno | Exterior, sol directo o lluvia, en movimiento | Al menos 2 tareas en exterior (o junto a ventana con luz solar); el resto en interior |
| Dispositivo | Apple Watch propio; tamaños 40–49 mm | Un reloj pequeño (40/41 mm) y uno grande (45/46/49 mm); el participante usa el de su talla si lo tiene |
| Datos | Etapa en curso de Sarria a Portomarín | Build **Debug** con escenarios DEMO (`-demo.scenario active`, `alert`, `nearby`, `finished`). Se informa al participante de que los datos son ficticios |
| Conectividad | Intermitente | Modo avión en parte de la sesión (tarea T5) |

## 3. Participantes (perfiles representativos)

Mínimo recomendado: **5 por perfil principal** (P1–P2) y **2–3 por perfil de accesibilidad** (P3–P6);
total orientativo 15–20. Un mismo participante puede cubrir varios perfiles.

| Id | Perfil | Criterio de inclusión | Configuración del reloj |
|---|---|---|---|
| P1 | Peregrino habitual | Ha hecho o va a hacer el Camino; usa reloj inteligente | Por defecto |
| P2 | Persona mayor | ≥ 65 años; uso ocasional de smartphone | Por defecto; repetir T1 con texto grande |
| P3 | Baja visión con VoiceOver | Usuario habitual de VoiceOver | VoiceOver activado; cortina de pantalla opcional |
| P4 | Baja visión con texto ampliado | Usa tamaño de texto grande o de accesibilidad | Tamaño de texto máximo de accesibilidad; Negrita; Aumentar contraste |
| P5 | Temblor / destreza reducida | Temblor esencial, Parkinson, artrosis de manos o similar | Por defecto; anotar si usa Corona Digital o toques |
| P6 | Daltonismo | Deuteranopía/protanopía/tritanopía declarada o detectada (test Ishihara) | Por defecto; ambos temas |

Exclusión: menores de edad; personas que no puedan dar consentimiento informado.

## 4. Tareas

Cada tarea empieza desde la pantalla indicada, con la app en primer plano. El moderador lee el
enunciado tal cual; no señala la pantalla ni nombra controles.

| Id | Enunciado al participante | Escenario de partida | Éxito si… | Criterio objetivo |
|---|---|---|---|---|
| T1 | «¿Cuántos kilómetros llevas hoy?» | `active`, inicio | Dice la distancia mostrada (≈ 4,2 km) | Respuesta correcta en **≤ 5 s** desde que mira el reloj; 0 toques |
| T2 | «¿Cuánto tiempo llevas caminando?» | `active`, inicio | Dice el tiempo (≈ 1 h 05 min) | **≤ 5 s**; ≤ 1 toque |
| T3 | «Tienes sed: ¿hay agua cerca y a qué distancia?» | `nearby`, inicio | Llega a la lista de agua (o la línea de agua más cercana) y dice nombre y distancia | **≤ 20 s**; ≤ 3 toques; 0 retrocesos |
| T4 | «Te acaba de vibrar el reloj. ¿Qué te dice? Abre más información» | `alert`, inicio (aviso de p01) | Explica que hay una fuente a ~250 m y abre su ficha | Comprensión correcta; ficha abierta en **≤ 15 s**; ≤ 2 toques |
| T5 | «¿Están guardados tus datos? ¿Se han enviado?» | `finished`, inicio, modo avión | Distingue «guardado en el reloj» de «pendiente de enviar» | Respuesta correcta en **≤ 20 s**; 0 interpretaciones de pérdida de datos |
| T6 | «Cambia los colores de la app a fondo claro» | `idle`, inicio | Tema Perla activo | **≤ 30 s**; ≤ 4 toques; ≤ 1 retroceso |

Notas:
- T1 y T2 miden lectura «de un vistazo» (levantar muñeca, entender). El cronómetro empieza cuando
  el participante gira la muñeca y la pantalla se ilumina.
- Con VoiceOver (P3) los tiempos objetivo se multiplican por 3 y se anota el número de gestos de
  desplazamiento en lugar de toques.
- Orden de tareas contrabalanceado (T1–T2 siempre primero; T3–T6 en orden rotado).

## 5. Métricas

| Dimensión ISO 9241-11 | Métrica | Cómo se mide |
|---|---|---|
| Eficacia | Tasa de éxito por tarea | Éxito completo = 1, parcial (con pista) = 0,5, fallo/abandono = 0 |
| Eficacia | Errores | Respuestas incorrectas, pantalla equivocada, toque fuera de objetivo (P5) |
| Eficiencia | Tiempo en tarea | Cronómetro / vídeo; desde fin del enunciado (o giro de muñeca en T1–T2) hasta respuesta |
| Eficiencia | Pulsaciones / gestos | Toques, giros de Corona, deslizamientos; con VoiceOver, gestos |
| Eficiencia | Retrocesos | Veces que vuelve atrás o abre una pantalla no necesaria |
| Satisfacción | SEQ (Single Ease Question) | Tras cada tarea, 1–7 («¿Cómo de fácil o difícil fue?») |
| Satisfacción | SUS (System Usability Scale) | Al final; 10 ítems, versión en español, puntuación 0–100 |
| Satisfacción | Comentarios | Pensamiento en voz alta + entrevista final |

## 6. Criterios de aceptación (objetivo V1)

| Criterio | Objetivo |
|---|---|
| Identificar estadísticas esenciales (T1, T2) | ≥ 90 % de éxito; mediana **≤ 5 s** |
| Agua cercana (T3) | ≥ 80 % de éxito; mediana ≤ 20 s |
| Comprensión del aviso (T4) | ≥ 90 % entiende tipo y distancia del POI; ≥ 80 % abre la ficha |
| Estado de datos (T5) | ≥ 80 % de éxito; **ningún** participante cree haber perdido datos |
| Cambio de tema (T6) | ≥ 80 % de éxito sin ayuda |
| SEQ medio por tarea | ≥ 5,5 |
| SUS medio | ≥ 75 (ningún perfil < 68) |
| Perfiles de accesibilidad (P3–P6) | Todas las tareas completables; ningún bloqueo (fallo debido a la app y no a la tarea) |
| Errores críticos | 0 (p. ej. finalizar la etapa sin querer, interpretar mal la distancia a un POI) |

Un criterio no alcanzado genera una incidencia con severidad (crítica / grave / leve) y la pantalla afectada.

## 7. Guion de la sesión (≈ 45 min)

1. **Bienvenida (3 min).** Presentación; «evaluamos la app, no a usted»; datos ficticios.
2. **Consentimiento (5 min).** Lectura y firma (§8). Confirmar permiso de grabación.
3. **Cuestionario previo (5 min).** Edad, experiencia con relojes, Camino, ayudas técnicas, ajustes de accesibilidad que usa.
4. **Ajuste del reloj (3 min).** Colocación en la muñeca habitual; configuración del perfil (§3). El moderador lanza el escenario con el reloj fuera de la vista del participante.
5. **Práctica (2 min).** Tarea neutra: «mira la hora».
6. **Tareas T1–T6 (20 min).** Pensamiento en voz alta. Tras cada tarea, SEQ. El moderador no ayuda salvo a los 2 min de bloqueo (se registra como «con pista»).
7. **SUS + entrevista (5 min).** «¿Qué le resultó más difícil?», «¿Lo usaría en el Camino?», «¿Qué cambiaría?».
8. **Cierre (2 min).** Agradecimiento; recordatorio de derechos sobre los datos.

Preparación por tarea (moderador, en Debug):

```
xcrun simctl launch --terminate-running-process <udid> org.caminoseguro.watch \
  -settings.theme negro -demo.scenario active
```

En reloj físico: lanzar desde Xcode con los mismos argumentos («Edit Scheme › Run › Arguments»).

## 8. Consentimiento informado (resumen a adaptar por el responsable legal)

- Objetivo del estudio y duración aproximada.
- Participación voluntaria; se puede abandonar en cualquier momento sin explicación.
- Qué se registra: notas, tiempos, respuestas a cuestionarios y, **sólo si se autoriza**, vídeo de
  la muñeca y audio. No se graba la cara salvo autorización expresa.
- No se usan datos de ubicación ni de salud reales del participante: la app funciona con datos DEMO.
- Datos seudonimizados (código de participante P1-01…); conservación limitada y acceso restringido;
  derechos de acceso, rectificación y supresión según RGPD (datos de contacto del responsable).
- Compensación, si la hay.
- Casillas separadas: participar ☐ · grabar audio ☐ · grabar vídeo de la muñeca ☐ · usar citas anónimas ☐.
- Firma del participante y del moderador, fecha.

## 9. Plantillas de registro

### 9.1 Ficha de participante

| Campo | Valor |
|---|---|
| Código | |
| Perfil(es) | P1 / P2 / P3 / P4 / P5 / P6 |
| Edad (rango) | |
| Reloj y tamaño | |
| Ajustes de accesibilidad | VoiceOver ☐ · Texto (tamaño) ___ · Negrita ☐ · Aumentar contraste ☐ · Otros ___ |
| Mano / muñeca | |
| Experiencia (relojes / Camino) | |
| Consentimiento firmado | ☐ |

### 9.2 Registro por tarea

| Tarea | Tema | Éxito (1 / 0,5 / 0) | Tiempo (s) | Toques / gestos | Retrocesos | Errores (descripción) | SEQ (1–7) | Observaciones / citas |
|---|---|---|---|---|---|---|---|---|
| T1 | | | | | | | | |
| T2 | | | | | | | | |
| T3 | | | | | | | | |
| T4 | | | | | | | | |
| T5 | | | | | | | | |
| T6 | | | | | | | | |

### 9.3 Resultado SUS

| Ítem | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | Total (0–100) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Respuesta (1–5) | | | | | | | | | | | |

### 9.4 Incidencias

| Id | Tarea | Pantalla | Descripción | Perfil(es) afectados | Nº participantes | Severidad | Norma / requisito relacionado (STANDARDS_MATRIX) | Propuesta |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |

### 9.5 Resumen agregado (por perfil y global)

| Tarea | Éxito (%) | Tiempo mediano (s) | Toques medianos | SEQ medio | ¿Cumple §6? |
|---|---|---|---|---|---|
| T1 | PENDIENTE | | | | |
| T2 | PENDIENTE | | | | |
| T3 | PENDIENTE | | | | |
| T4 | PENDIENTE | | | | |
| T5 | PENDIENTE | | | | |
| T6 | PENDIENTE | | | | |
| SUS medio | PENDIENTE | | | | |

## 10. Limitaciones

- Los escenarios DEMO no reproducen el movimiento real ni la vibración real de un aviso en el
  momento exacto; T4 simula la situación tras la vibración.
- Las pruebas en interior no sustituyen la legibilidad al sol (tema Perla vs. Negro).
- Muestra pequeña: los resultados son cualitativos para perfiles P3–P6.
