import processing.serial.*;

import processing.serial.*;

Serial puerto;
float xPos = 1, lastX = 1, lastY = 200, lastYPulso = 490;
int valorECG = 512, contadorCiclo = 0;
int modoSimulacion = 1;

int[] ondaNormal = {0, 0, 10, 20, 10, 0, 0, -15, 140, 100, -35, 0, 0, 0, 15, 30, 45, 30, 15};
int[] ondaInfarto = {0, 0, 10, 20, 10, 0, 0, -15, 140, 100, -35, 40, 45, 50, 45, 30, 15};
int[] ondaFibrilacion = {40, -50, 60, -20, 80, -70, 30, -40, 50, -10};
int[] ondaActual = ondaNormal;

int pausaActual = 25;
String nombreEstado = "RITMO SINUSAL NORMAL";
color colorEstado = color(0, 255, 0);

void setup() {
  size(1000, 500); 
  background(10, 15, 10); 
  frameRate(50); 
  
  if (Serial.list().length > 0) {
    puerto = new Serial(this, Serial.list()[0], 9600);
  }
  dibujarCuadriculaCompleta();
}

void draw() {
  int ruido = int(random(-4, 5)); 
  int valorBase = 0;
  
  if (contadorCiclo < ondaActual.length) valorBase = ondaActual[contadorCiclo];
  if (modoSimulacion == 6) valorBase = 0; 
  
  valorECG = 512 + (valorBase * 2) + ruido; 
  
  if (contadorCiclo == 8 && modoSimulacion < 5) {
    if (puerto != null) puerto.write('B'); 
  }
  if (modoSimulacion >= 4 && frameCount % 25 == 0) {
    if (puerto != null) puerto.write('A'); 
  }
  
  contadorCiclo++;
  
  if (contadorCiclo >= ondaActual.length + pausaActual) {
    contadorCiclo = 0;
    switch(modoSimulacion) {
      case 1: ondaActual = ondaNormal; pausaActual = 25; nombreEstado = "RITMO SINUSAL NORMAL"; colorEstado = color(0, 255, 0); break;
      case 2: ondaActual = ondaNormal; pausaActual = 5; nombreEstado = "TAQUICARDIA"; colorEstado = color(255, 200, 0); break;
      case 3: ondaActual = ondaNormal; pausaActual = 60; nombreEstado = "BRADICARDIA"; colorEstado = color(0, 150, 255); break;
      case 4: ondaActual = ondaInfarto; pausaActual = 25; nombreEstado = "INFARTO (ELEVACIÓN ST)"; colorEstado = color(255, 0, 0); break;
      case 5: ondaActual = ondaFibrilacion; pausaActual = 0; nombreEstado = "FIBRILACIÓN VENTRICULAR"; colorEstado = color(255, 0, 0); break;
      case 6: ondaActual = ondaNormal; pausaActual = 1000; nombreEstado = "ASISTOLIA (PARO)"; colorEstado = color(255, 0, 0); break;
    }
  }
  
  // 1. EFECTO BORRADOR: Limpiamos un margen por delante de la onda
  noStroke();
  fill(10, 15, 10);
  rect(xPos, 50, 40, height - 50);
  
  // 2. REDIBUJO DE CUADRÍCULA: Pintamos la grilla SÓLO en el pedacito recién borrado
  stroke(20, 50, 20);
  strokeWeight(1);
  for (int i = int(xPos); i < xPos + 40; i++) {
    if (i % 20 == 0 && i < width - 250) line(i, 50, i, height); // Líneas verticales
  }
  for (int i = 50; i < height; i += 20) {
    if (xPos < width - 250) line(xPos, i, min(xPos + 40, width - 250), i); // Líneas horizontales
  }
  
  // 3. TRAZADO DEL ECG (Señal principal)
  // Ajustamos el mapa para no pisar la zona del marcador inferior
  float yPos = map(valorECG, 0, 1023, height - 80, 60); 
  stroke(0, 255, 100); 
  strokeWeight(3);
  line(lastX, lastY, xPos, yPos); 
  lastX = xPos; 
  lastY = yPos;
  
  // 4. MARCADOR DE PULSO INFERIOR (Sync track)
  // Genera un pulso cuadrado amarillo durante los índices 8, 9 y 10 del latido
  float yPulso = (contadorCiclo >= 8 && contadorCiclo <= 10 && modoSimulacion < 5) ? height - 40 : height - 10;
  stroke(255, 200, 0); // Color amarillo
  strokeWeight(2);
  line(lastX, lastYPulso, xPos, yPulso);
  lastYPulso = yPulso;
  
  // AVANCE Y REINICIO DE PANTALLA
  xPos += 3; 
  if (xPos >= width - 250) { 
    xPos = 1;
    lastX = 1;
    lastYPulso = height - 10; // Reinicia la posición de la recta inferior
    dibujarCuadriculaCompleta(); 
  }
  
  dibujarPanelLateral();
}

void dibujarCuadriculaCompleta() {
  background(10, 15, 10);
  stroke(20, 50, 20);
  strokeWeight(1);
  for (int i = 0; i < width - 250; i += 20) line(i, 50, i, height);
  for (int i = 50; i < height; i += 20) line(0, i, width - 250, i);
}

void dibujarPanelLateral() {
  noStroke(); fill(20); rect(width - 250, 0, 250, height);
  fill(0); rect(0, 0, width, 50); 
  
  int totalFramesLatido = ondaActual.length + pausaActual;
  int bpm = (modoSimulacion == 6 || modoSimulacion == 5) ? 0 : 3000 / totalFramesLatido;
  
  fill(colorEstado);
  textSize(24); textAlign(CENTER, CENTER);
  text(nombreEstado, width/2 - 125, 25); 
  
  textAlign(LEFT, TOP);
  textSize(60); text(bpm, width - 230, 80);
  textSize(20); fill(150); text("BPM", width - 230, 150);
  
  textSize(35); fill(0, 255, 100); text(valorECG, width - 230, 220);
  textSize(20); fill(150); text("ADC RAW", width - 230, 260);
  
  textSize(14); fill(100);
  text("CONTROLES (Teclado):", width - 230, height - 180);
  text("1 - Normal\n2 - Taquicardia\n3 - Bradicardia\n4 - Infarto\n5 - Fibrilación\n6 - Paro Cardíaco", width - 230, height - 150);
}

void keyPressed() {
  if (key >= '1' && key <= '6') {
    modoSimulacion = key - '0';
    contadorCiclo = 0; 
  }
}
