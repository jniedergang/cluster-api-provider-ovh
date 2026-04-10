/*
Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// Package metrics defines Prometheus metrics for CAPIOVH controllers.
package metrics

import (
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
)

const (
	namespace = "capiovh"
)

var (
	// Machine lifecycle metrics.

	// MachineCreateTotal counts instance creation attempts.
	MachineCreateTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Namespace: namespace,
		Name:      "machine_create_total",
		Help:      "Total number of OVH instance creation attempts",
	})

	// MachineCreateErrorsTotal counts instance creation failures.
	MachineCreateErrorsTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Namespace: namespace,
		Name:      "machine_create_errors_total",
		Help:      "Total number of OVH instance creation errors",
	})

	// MachineCreationDuration tracks instance creation time.
	MachineCreationDuration = prometheus.NewHistogram(prometheus.HistogramOpts{
		Namespace: namespace,
		Name:      "machine_creation_duration_seconds",
		Help:      "Time taken to create an OVH instance (from API call to ACTIVE status)",
		Buckets:   []float64{10, 30, 60, 120, 180, 300, 600},
	})

	// MachineDeleteTotal counts instance deletion attempts.
	MachineDeleteTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Namespace: namespace,
		Name:      "machine_delete_total",
		Help:      "Total number of OVH instance deletion attempts",
	})

	// MachineDeleteErrorsTotal counts instance deletion failures.
	MachineDeleteErrorsTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Namespace: namespace,
		Name:      "machine_delete_errors_total",
		Help:      "Total number of OVH instance deletion errors",
	})

	// MachineStatus tracks machine readiness per cluster.
	MachineStatus = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: namespace,
		Name:      "machine_status",
		Help:      "Current status of OVH machines (1=ready, 0=not ready)",
	}, []string{"cluster", "machine"})

	// MachineReconcileDuration tracks reconciliation time.
	MachineReconcileDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Namespace: namespace,
		Name:      "machine_reconcile_duration_seconds",
		Help:      "Duration of OVHMachine reconciliation",
		Buckets:   prometheus.DefBuckets,
	}, []string{"operation"}) // operation: "normal" or "delete"

	// Cluster lifecycle metrics.

	// ClusterReconcileDuration tracks cluster reconciliation time.
	ClusterReconcileDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Namespace: namespace,
		Name:      "cluster_reconcile_duration_seconds",
		Help:      "Duration of OVHCluster reconciliation",
		Buckets:   prometheus.DefBuckets,
	}, []string{"operation"})

	// ClusterReady tracks cluster readiness.
	ClusterReady = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: namespace,
		Name:      "cluster_ready",
		Help:      "Current readiness status of OVH clusters (1=ready, 0=not ready)",
	}, []string{"cluster"})
)

func init() {
	metrics.Registry.MustRegister(
		MachineCreateTotal,
		MachineCreateErrorsTotal,
		MachineCreationDuration,
		MachineDeleteTotal,
		MachineDeleteErrorsTotal,
		MachineStatus,
		MachineReconcileDuration,
		ClusterReconcileDuration,
		ClusterReady,
	)
}
