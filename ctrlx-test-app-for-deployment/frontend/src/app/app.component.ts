/**
 * Angular controller component for the ctrlX Dashboard.
 * 
 * Periodically polls the Flask REST API for system metrics
 * and provides read-only tracking of operating states.
 */

import { Component, OnInit, OnDestroy } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Subscription, interval } from 'rxjs';
import { startWith, switchMap } from 'rxjs/operators';

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

  constructor(private http: HttpClient) {}

  ngOnInit(): void {
    // Polls the Flask API endpoint every 3000ms
    this.pollSub = interval(3000).pipe(
      startWith(0),
      switchMap(() => this.http.get<SystemMetrics>('/api/metrics'))
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
   * Helper to format raw API numeric values cleanly.
   */
  formatValue(value: number | string): number {
    return typeof value === 'number' ? Math.round(value) : 0;
  }
}
