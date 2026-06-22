import { Injectable, isDevMode } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, Subject } from 'rxjs';
import { io, Socket } from 'socket.io-client';

@Injectable({
  providedIn: 'root'
})
export class DashboardService {
  // REST-Endpunkte für den State-Wechsel (bleibt auf /api)
  private apiUrl = isDevMode() ? 'http://localhost:5001/api' : '/api';
  
  // WebSocket-Verbindungs-URL (im Dev-Modus Port 5001, im Produktionsmodus relativ)
  private wsUrl = isDevMode() ? 'http://localhost:5001' : ''; 
  
  private socket!: Socket;
  private metrics$ = new Subject<any>();

  constructor(private http: HttpClient) {
    // Initialisiere die Socket.io-Verbindung
    this.socket = io(this.wsUrl, {
      transports: ['websocket', 'polling']
    });

    // Registriere den Listener für den 'metrics_update'-Kanal von Flask
    this.socket.on('metrics_update', (data: any) => {
      this.metrics$.next(data);
    });

    // Logging zur Unterstützung der Inbetriebnahme
    this.socket.on('connect', () => {
      console.log('[WebSocket] Successfully connected to ctrlX CORE Backend');
    });

    this.socket.on('disconnect', () => {
      console.warn('[WebSocket] Connection to backend lost');
    });
  }

  /**
   * Gibt den Live-Datenstrom der Steuerung als Observable zurück.
   * Ersetzt das manuelle getMetrics()-Polling in den Komponenten.
   */
  getLiveMetrics(): Observable<any> {
    return this.metrics$.asObservable();
  }

  /**
   * Sendet den Befehl zur Umschaltung des Systemzustands (OPERATING, SETUP, SERVICE)
   * weiterhin über die REST-Schnittstelle.
   */
  setSchedulerState(state: string): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/state`, { state });
  }
}
