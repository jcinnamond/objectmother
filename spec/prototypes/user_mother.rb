class UserMother < ObjectMother
  def user_prototype
    {
      :name => 'some_user',
      :pet => false
    }
  end
end