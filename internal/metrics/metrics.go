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

	// Workload-side lifecycle metrics.

	// NodeInitDuration tracks the time to patch providerID and remove the
	// uninitialized taint on a workload node after the instance is ACTIVE.
	NodeInitDuration = prometheus.NewHistogram(prometheus.HistogramOpts{
		Namespace: namespace,
		Name:      "node_init_duration_seconds",
		Help:      "Time to initialize a workload node (patch providerID, remove uninitialized taint)",
		Buckets:   []float64{1, 5, 10, 30, 60, 120, 300},
	})

	// EtcdMemberRemovalDuration tracks the time to remove an etcd member on CP deletion.
	EtcdMemberRemovalDuration = prometheus.NewHistogram(prometheus.HistogramOpts{
		Namespace: namespace,
		Name:      "etcd_member_removal_duration_seconds",
		Help:      "Time to remove an etcd member from the workload cluster when deleting a CP machine",
		Buckets:   []float64{1, 5, 10, 30, 60, 120},
	})

	// BootstrapWaitDuration tracks the OVH instance BUILD -> ACTIVE delay.
	BootstrapWaitDuration = prometheus.NewHistogram(prometheus.HistogramOpts{
		Namespace: namespace,
		Name:      "bootstrap_wait_duration_seconds",
		Help:      "Time an OVH instance spent in BUILD state before reaching ACTIVE",
		Buckets:   []float64{30, 60, 120, 180, 300, 600, 900},
	})

	// LBPollDuration tracks the find-by-name polling loop after an async LB POST.
	LBPollDuration = prometheus.NewHistogram(prometheus.HistogramOpts{
		Namespace: namespace,
		Name:      "lb_poll_duration_seconds",
		Help:      "Time to resolve a newly-created load balancer via find-by-name after the async POST",
		Buckets:   []float64{1, 5, 10, 30, 60, 110},
	})

	// OVH API metrics.

	// OVHAPIRequestsTotal counts OVH API requests by endpoint group and outcome.
	OVHAPIRequestsTotal = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace,
		Name:      "ovh_api_requests_total",
		Help:      "Total number of OVH API requests, labelled by endpoint group and outcome",
	}, []string{"endpoint", "outcome"}) // outcome: "ok" | "error" | "retry"

	// OVHAPIRequestDuration tracks OVH API request latency per endpoint group.
	OVHAPIRequestDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Namespace: namespace,
		Name:      "ovh_api_request_duration_seconds",
		Help:      "Duration of OVH API requests per endpoint group",
		Buckets:   prometheus.DefBuckets,
	}, []string{"endpoint"})
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
		NodeInitDuration,
		EtcdMemberRemovalDuration,
		BootstrapWaitDuration,
		LBPollDuration,
		OVHAPIRequestsTotal,
		OVHAPIRequestDuration,
	)
}
