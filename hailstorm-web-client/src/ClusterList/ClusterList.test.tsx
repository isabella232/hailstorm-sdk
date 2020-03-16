import React from 'react';
import { shallow, mount } from 'enzyme';
import { ClusterList } from './ClusterList';
import { render, fireEvent } from '@testing-library/react';
import { Cluster } from '../domain';

describe('<ClusterList />', () => {
  it('should render without crashing', () => {
    shallow(<ClusterList />);
  });

  it('should show clusters list', () => {
    const component = mount(
      <ClusterList clusters={[
        {id: 1, type: 'AWS', title: 'AWS us-east-1', code: 'aws-1' }
      ]} />
    );

    expect(component).toContainMatchingElements(1, '.panel-block');
  });

  it('should select a cluster', async () => {
    const onSelectCluster = jest.fn();
    const {findByText, debug} = render(
      <ClusterList
        clusters={[
          {id: 1, type: 'AWS', title: 'AWS us-east-1', code: 'aws-1' },
          {id: 2, type: 'AWS', title: 'AWS us-west-1', code: 'aws-2' },
        ]}
        {...{onSelectCluster}}
        activeCluster={{id: 2, type: 'AWS', title: 'AWS us-west-1', code: 'aws-2' }}
      />
    );

    const clusterTwo = await findByText('AWS us-west-1');
    expect(clusterTwo.classList).toContain('is-active');

    const clusterOne = await findByText('AWS us-east-1');
    fireEvent.click(clusterOne);
    expect(onSelectCluster).toBeCalled();
    const invoked = onSelectCluster.mock.calls[0][0] as Cluster;
    expect(invoked.code).toEqual('aws-1');
  });

  it('should disable edit', () =>{
    const wrapper = shallow(<ClusterList disableEdit={true} showEdit={true} />);
    expect(wrapper.find('.button')).toBeDisabled();
  });
});
