import React from 'react';
import { Cluster } from '../domain';

export const ClusterList: React.FC<{
  clusters?: Cluster[];
  hideEdit?: boolean;
}> = ({clusters, hideEdit}) => {
  return (
    <div className="panel">
      <div className="panel-heading">
        <div className="level">
          <div className="level-left">
            <div className="level-item">
              <i className="fas fa-globe-americas"></i> Clusters
            </div>
          </div>
          <div className="level-right">
            <div className="level-item">
              {!hideEdit && (
              <a className="button is-small"><i className="far fa-edit"></i> Edit</a>
              )}
            </div>
          </div>
        </div>
      </div>
      {clusters !== undefined ? (
      clusters.map(cluster => (
        <a className="panel-block" key={cluster.id}>
          <span className="panel-icon">
            <i className="fas fa-server" aria-hidden="true"></i>
          </span>
          {cluster.title}
        </a>
      ))
      ) : (
      <>
      <div className="panel-block"></div>
      <div className="panel-block"></div>
      <div className="panel-block"></div>
      </>
      )}
    </div>
  );
}
