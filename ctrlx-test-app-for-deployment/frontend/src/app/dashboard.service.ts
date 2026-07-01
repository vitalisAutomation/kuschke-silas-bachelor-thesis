import { Injectable, isDevMode } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, Subject } from 'rxjs';
import { io, Socket } from 'socket.io-client';

@Injectable({
  providedIn: 'root'
})
export class DashboardService {
  // REST-API: Use secure local port in Dev Mode, or the mapped ctrlX proxy path in Production
  private apiUrl = isDevMode() 
    ? 'https://localhost:5001/api' 
    : '/ctrlx-cockpit/api';
  
  // WebSockets: Point to the proxy route with the correct socket path in Production
  private wsUrl = isDevMode() ? 'https://localhost:5001' : ''; 
  private socket!: Socket;
  private metrics$ = new Subject<any>();

  constructor(private http: HttpClient) {
    // Connect configuration suited for ctrlX OS Reverse Proxy routing
    const socketOptions = isDevMode() 
      ? {
          transports: ['websocket', 'polling'],
          rejectUnauthorized: false // Allow self-signed certs in Dev Mode
        }
      : {
          transports: ['websocket', 'polling'],
          path: '/ctrlx-cockpit/socket.io' // Force Socket.io to route through Nginx Proxy!
        };

    // Initialize Socket.io connection
    this.socket = io(this.wsUrl, socketOptions);

    this.socket.on('metrics_update', (data: any) => {
      this.metrics$.next(data);
    });

    this.socket.on('connect', () => {
      console.log('[WebSocket] Successfully connected via ctrlX Proxy (WSS)');
    });

    this.socket.on('disconnect', () => {
      console.warn('[WebSocket] Proxy connection lost');
    });
  }

  getLiveMetrics(): Observable<any> {
    return this.metrics$.asObservable();
  }

  setSchedulerState(state: string): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/state`, { state });
  }
}
