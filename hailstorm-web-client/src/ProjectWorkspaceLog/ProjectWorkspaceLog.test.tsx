import React from 'react';
import { mount, render } from 'enzyme';
import { ProjectWorkspaceLog } from './ProjectWorkspaceLog';
import { Project } from '../domain';
import { LogStream } from '../stream';
import { of } from 'rxjs';
import { AppStateContext } from '../appStateContext';

describe('<ProjectWorkspaceLog />', () => {
  afterEach(() => {
    jest.resetAllMocks();
  });

  it('should render without crashing', () => {
    const project: Project = {id: 1, code: 'a', title: 'A', running: true, autoStop: false};
    render(
      <AppStateContext.Provider value={{appState: {activeProject: project, runningProjects: []}, dispatch: jest.fn()}}>
        <ProjectWorkspaceLog />
      </AppStateContext.Provider>
    );
  });

  it('should update logs as they are received', () => {
    const project: Project = {id: 1, code: 'a', title: 'A', running: true, autoStop: false};
    const logStreamSpy = jest.spyOn(LogStream, '_logSource').mockImplementation(() => of(
      {projectCode: project.code, timestamp: 1565759983, priority: 2, level: 'info', message: 'Starting Tests...'},
      {projectCode: project.code, timestamp: 1565760004, priority: 2, level: 'info', message: `Creating Cluster in us-east-1...`},
      {projectCode: project.code, timestamp: 1565780014, priority: 2, level: 'info', message: `Creating Cluster in us-west-1...`},
    ));
    const component = mount(
      <AppStateContext.Provider value={{appState: {activeProject: project, runningProjects: []}, dispatch: jest.fn()}}>
        <ProjectWorkspaceLog />
      </AppStateContext.Provider>
    );

    expect(logStreamSpy).toHaveBeenCalled();
    setTimeout(() => {
      expect(component).toContainMatchingElements(3, '.logBox br');
    }, 0);
  });
});