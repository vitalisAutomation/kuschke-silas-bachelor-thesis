import { Injectable, isDevMode } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

@Injectable({
  providedIn: 'root'
})
export class DashboardService {
  private apiUrl = isDevMode() ? 'http://localhost:5001/api' : '/api';

  constructor(private http: HttpClient) { }

  getMetrics(): Observable<any> {
    return this.http.get<any>(`${this.apiUrl}/metrics`);
  }

  setSchedulerState(state: string): Observable<any> {
    return this.http.post<any>(`${this.apiUrl}/state`, { state });
  }
}
