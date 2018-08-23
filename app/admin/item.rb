ActiveAdmin.register Item do
  menu parent: 'Videos'

  permit_params :subscription_id, :video_id, :state

  controller do
    def scoped_collection
      super.includes :video, subscription: [:user, :channel]
    end
  end

  index do
    column :video, sortable: 'videos.title'
    column :subscription
    column :user, sortable: 'users.email'
    column :channel, sortable: 'channels.title'
    column :state do |item|
      Item::STATE_LABELS[Item.states[item.state]]
    end
    column :created_at
    column :updated_at
    actions
  end

  filter :state, as: :select, collection: Item::STATE_LABELS.zip(Item.states.values)
  filter :video_title, as: :string
  filter :user_email, as: :string
  filter :channel_title, as: :string

  form do |_f|
    semantic_errors
    inputs 'Details' do
      input :video
      input :subscription
      input :state, as: :select, collection: Item::STATE_LABELS.zip(Item.states.keys), include_blank: false
    end
    actions
  end
end
