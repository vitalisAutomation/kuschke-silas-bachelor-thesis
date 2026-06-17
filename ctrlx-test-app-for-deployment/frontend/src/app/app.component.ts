/**
 * Angular controller component for the ctrlX Dashboard.
 *
 * Periodically polls the backend REST API for system metrics. The API URL
 * is determined by the environment configuration.
 */

import { Component, OnInit, OnDestroy } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Subscription, interval } from 'rxjs';
import { startWith, switchMap } from 'rxjs/operators';

// Import the environment configuration to get the correct API URL
import { environment } from '../environments/environment';

interface SystemMetrics {
  state: string;
  cpu: number | string;
  ram_used_percent: number | string;
  storage_used_percent: number | string;
}

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css']
})
export class AppComponent implements OnInit, OnDestroy {
  metrics: SystemMetrics = { state: 'LOADING', cpu: 0, ram_used_percent: 0, storage_used_percent: 0 };
  private pollSub!: Subscription;
  
  // Construct the full API URL based on the current environment
  private readonly apiUrl = `${environment.apiUrl}/metrics`;

  constructor(private http: HttpClient) {}

  ngOnInit(): void {
    // Poll the backend API endpoint every 3000ms
    this.pollSub = interval(3000).pipe(
      startWith(0),
      // Use the dynamically constructed API URL for the request
      switchMap(() => this.http.get<SystemMetrics>(this.apiUrl))
    ).subscribe({
      next: (data) => {
        this.metrics = data;
      },
      error: (err) => {
        console.error('Error retrieving system metrics:', err);
        this.metrics.state = 'ERROR';
      }
    });
  }

  ngOnDestroy(): void {
    if (this.pollSub) {
      this.pollSub.unsubscribe();
    }
  }

  /**
   * Helper to format raw API numeric values cleanly for the UI.
   */
  formatValue(value: number | string): number {
    return typeof value === 'number' ? Math.round(value) : 0;
  }
}
