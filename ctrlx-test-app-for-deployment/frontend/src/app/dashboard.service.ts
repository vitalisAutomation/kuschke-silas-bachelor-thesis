import { Injectable, isDevMode } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, Subject } from 'rxjs';
import { io, Socket } from 'socket.io-client';

@Injectable({
  providedIn: 'root'
})
export class DashboardService {
  // REST-API: Im Dev-Modus HTTPS aktiv, in Produktion relative Pfade
  private apiUrl = isDevMode() ? 'https://localhost:5001/api' : '/api';
  
  // WebSockets: Im Dev-Modus WSS aktiv, in Produktion relative Pfade
  private wsUrl = isDevMode() ? 'https://localhost:5001' : ''; 
  
  private socket!: Socket;
  private metrics$ = new Subject<any>();

  constructor(private http: HttpClient) {
    // Initialisiere die verschlüsselte Socket.io-Verbindung
    this.socket = io(this.wsUrl, {
      transports: ['websocket', 'polling'],
      rejectUnauthorized: false // WICHTIG: Erlaubt selbstsignierte Zertifikate im Dev-Modus
    });

    this.socket.on('metrics_update', (data: any) => {
      this.metrics$.next(data);
    });

    this.socket.on('connect', () => {
      console.log('[WebSocket] Successfully connected via Secure WSS');
    });

    this.socket.on('disconnect', () => {
      console.warn('[WebSocket] Secure connection lost');
    });
  }

  getLiveMetrics(): Observable<any> {
    return this.metrics$.asObservable();
  }

  setSchedulerState(state: string): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/state`, { state });
  }
}
